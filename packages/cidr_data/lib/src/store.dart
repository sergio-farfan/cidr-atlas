// CIDR Atlas
// SQLite inventory persistence and atomic imports.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cidr_core/cidr_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart' as sqlite_loader;

import 'import.dart';

class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.summary,
    required this.at,
  });

  final String action;
  final String summary;
  final DateTime at;
}

class InventoryConflictException implements Exception {
  InventoryConflictException(List<Conflict> conflicts)
      : conflicts = List.unmodifiable(conflicts);

  final List<Conflict> conflicts;

  @override
  String toString() =>
      'Allocation conflicts: ${conflicts.map((conflict) => conflict.reason).join(' ')}';
}

/// A single local inventory. Writes validate and commit the complete structure
/// atomically; routing conflicts deliberately remain visible in the register.
class InventoryStore {
  InventoryStore._(this._database) {
    try {
      _database.execute('PRAGMA busy_timeout = 5000');
      _database.execute('PRAGMA foreign_keys = ON');
      final version =
          _database.select('PRAGMA user_version').first.values.first as int;
      if (version > 1) {
        throw StateError(
          'This database needs a newer version of CIDR Atlas (schema $version).',
        );
      }
      if (version == 0) {
        _transaction(() {
          _database.execute(
            'CREATE TABLE IF NOT EXISTS prefixes (id TEXT PRIMARY KEY NOT NULL, document TEXT NOT NULL)',
          );
          _database.execute(
            'CREATE TABLE IF NOT EXISTS audit_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT NOT NULL, summary TEXT NOT NULL, at TEXT NOT NULL)',
          );
          _database.execute('PRAGMA user_version = 1');
        });
      }
    } catch (_) {
      _database.dispose();
      rethrow;
    }
  }

  factory InventoryStore.open(String path) {
    if (path.trim().isEmpty)
      throw ArgumentError('Database path cannot be blank.');
    File(path).parent.createSync(recursive: true);
    _prepareSqlite();
    return InventoryStore._(sqlite3.open(path));
  }

  factory InventoryStore.memory() {
    _prepareSqlite();
    return InventoryStore._(sqlite3.openInMemory());
  }

  static bool _prepared = false;

  static void _prepareSqlite() {
    if (_prepared) return;
    if (Platform.isLinux) {
      // Runtime packages commonly install only the versioned soname; the
      // unversioned name is often supplied by an unnecessary development kit.
      sqlite_loader.open.overrideFor(sqlite_loader.OperatingSystem.linux, () {
        try {
          return DynamicLibrary.open('libsqlite3.so.0');
        } on ArgumentError {
          return DynamicLibrary.open('libsqlite3.so');
        }
      });
    }
    _prepared = true;
  }

  final Database _database;
  bool _closed = false;

  List<PrefixRecord> list() {
    _ensureOpen();
    return _database
        .select('SELECT document FROM prefixes ORDER BY id')
        .map((row) {
      return PrefixRecord.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(row['document'] as String) as Map,
        ),
      );
    }).toList(growable: false);
  }

  void save(PrefixRecord record, {bool rejectConflicts = false}) =>
      _saveRecords([record], action: 'save', rejectConflicts: rejectConflicts);

  /// Creates a new nonconflicting reservation, rechecking the latest inventory
  /// and record identity inside the same transaction as the write and audit.
  void reserve(PrefixRecord record) => _saveRecords(
        [record],
        action: 'reserve',
        rejectConflicts: true,
        requireNew: true,
      );

  void saveAll(List<PrefixRecord> records, {bool rejectConflicts = false}) =>
      _saveRecords(records, action: 'save', rejectConflicts: rejectConflicts);

  void _saveRecords(List<PrefixRecord> records,
      {required String action,
      required bool rejectConflicts,
      bool requireNew = false}) {
    _ensureOpen();
    if (records.isEmpty) return;
    _transaction(() {
      _checkDuplicateIds(records);
      final combined = {for (final item in list()) item.id: item};
      for (final record in records) {
        if (requireNew && combined.containsKey(record.id)) {
          throw FormatException('A prefix with id ${record.id} already exists. '
              'Recalculate the recommendation before reserving.');
        }
        combined[record.id] = record;
      }
      _validate(combined.values.toList());
      if (rejectConflicts) {
        final changedIds = records.map((record) => record.id).toSet();
        final conflicts = InventoryRules.conflicts(combined.values.toList())
            .where((conflict) =>
                changedIds.contains(conflict.first.id) ||
                changedIds.contains(conflict.second.id))
            .toList();
        if (conflicts.isNotEmpty) throw InventoryConflictException(conflicts);
      }
      _write(records);
      _audit(
        action,
        'Saved ${records.length} prefix record${records.length == 1 ? '' : 's'}: '
        '${records.map((record) => '${record.name} (${record.cidr}, ${record.routingDomain})').join('; ')}.',
      );
    });
  }

  void delete(String id) {
    _ensureOpen();
    _transaction(() {
      final current = list();
      if (!current.any((record) => record.id == id)) return;
      _validate(current.where((record) => record.id != id).toList());
      _database.execute('DELETE FROM prefixes WHERE id = ?', [id]);
      _audit('delete', 'Deleted prefix $id.');
    });
  }

  void applyImport(ImportPreview preview) {
    _ensureOpen();
    _transaction(() {
      final combined = mergedImportRecords(preview);
      _write(combined);
      _audit(
        'import',
        'Imported ${preview.records.length} prefixes from ${preview.source}. '
            'Coverage is not authoritative: absent records were retained, never deleted or retired. '
            '${preview.warnings.join(' ')}',
      );
    });
  }

  /// Returns the complete proposed inventory using the same reconciliation as
  /// [applyImport], without writing. Throws [FormatException] for a bad preview,
  /// ambiguous OCI identities, or invalid structure in the combined inventory.
  /// Routing conflicts are allowed and may be inspected with InventoryRules.
  List<PrefixRecord> mergedImportRecords(ImportPreview preview) {
    _ensureOpen();
    if (!preview.canApply) {
      throw FormatException(
        preview.errors.isEmpty
            ? 'Import contains no records.'
            : preview.errors.join('\n'),
      );
    }
    _checkDuplicateIds(preview.records);
    final current = {for (final item in list()) item.id: item};
    final aliases = <String, String>{};
    final ociImport = preview.source == 'OCI JSON';
    if (ociImport) {
      for (final incoming in preview.records) {
        final matches = current.values
            .where((existing) =>
                existing.resourceId.isNotEmpty &&
                existing.resourceId == incoming.resourceId &&
                existing.kind == incoming.kind &&
                Cidr.parse(existing.cidr).canonical ==
                    Cidr.parse(incoming.cidr).canonical &&
                existing.routingDomain == incoming.routingDomain &&
                _sameKnownScope(existing.tenancy, incoming.tenancy) &&
                _sameKnownScope(existing.region, incoming.region))
            .toList();
        if (matches.length > 1) {
          throw FormatException(
              'Multiple existing records match OCI resource ${incoming.resourceId} and ${incoming.cidr}; resolve duplicate inventory records first.');
        }
        aliases[incoming.id] =
            matches.isEmpty ? incoming.id : matches.single.id;
      }
      if (aliases.values.toSet().length != aliases.length) {
        throw const FormatException(
            'Multiple imported OCI prefixes map to one existing record.');
      }
    }
    for (final incoming in preview.records) {
      final targetId = aliases[incoming.id] ?? incoming.id;
      final existing = current[targetId];
      final normalized = incoming.copyWith(
        id: targetId,
        parentId: aliases[incoming.parentId] ?? incoming.parentId,
      );
      final record = existing != null && ociImport && incoming.source == 'oci'
          ? normalized.copyWith(
              owner: existing.owner,
              notes: existing.notes,
              status: existing.status,
              parentId: existing.parentId,
              environment: existing.environment,
              customer: existing.customer,
              verifiedAt: incoming.verifiedAt ?? existing.verifiedAt,
              tenancy: incoming.tenancy.isEmpty
                  ? existing.tenancy
                  : incoming.tenancy,
              region:
                  incoming.region.isEmpty ? existing.region : incoming.region,
              compartment: incoming.compartment.isEmpty
                  ? existing.compartment
                  : incoming.compartment,
            )
          : normalized;
      current[record.id] = record;
    }
    if (ociImport) {
      for (final incoming in preview.records) {
        final targetId = aliases[incoming.id] ?? incoming.id;
        final child = current[targetId]!;
        if (child.kind != PrefixKind.subnet ||
            child.parentId.isNotEmpty ||
            child.vcnId.isEmpty) continue;
        final parents = current.values
            .where((candidate) =>
                candidate.kind == PrefixKind.vcn &&
                candidate.resourceId == child.vcnId &&
                candidate.routingDomain == child.routingDomain &&
                _sameKnownScope(candidate.tenancy, child.tenancy) &&
                _sameKnownScope(candidate.region, child.region) &&
                Cidr.parse(candidate.cidr).contains(Cidr.parse(child.cidr)))
            .toList();
        if (parents.isEmpty) continue;
        parents.sort((a, b) => Cidr.parse(b.cidr)
            .prefixLength
            .compareTo(Cidr.parse(a.cidr).prefixLength));
        if (parents.length > 1 &&
            Cidr.parse(parents[0].cidr).prefixLength ==
                Cidr.parse(parents[1].cidr).prefixLength) {
          throw FormatException(
              'Subnet ${child.name} has ambiguous matching VCN parent records.');
        }
        final parent = parents.first;
        current[targetId] = child.copyWith(
          parentId: parent.id,
          tenancy: child.tenancy.isEmpty ? parent.tenancy : child.tenancy,
          region: child.region.isEmpty ? parent.region : child.region,
          compartment: child.compartment.isEmpty
              ? parent.compartment
              : child.compartment,
        );
      }
    }
    _validate(current.values.toList());
    return List.unmodifiable(current.values);
  }

  static bool _sameKnownScope(String first, String second) =>
      first.isEmpty || second.isEmpty || first == second;

  List<AuditEntry> history({int limit = 100}) {
    _ensureOpen();
    if (limit < 0)
      throw ArgumentError.value(limit, 'limit', 'Must be nonnegative.');
    return _database.select(
      'SELECT action, summary, at FROM audit_entries ORDER BY id DESC LIMIT ?',
      [limit],
    ).map((row) {
      return AuditEntry(
        action: row['action'] as String,
        summary: row['summary'] as String,
        at: DateTime.parse(row['at'] as String),
      );
    }).toList(growable: false);
  }

  void close() {
    if (!_closed) {
      _database.dispose();
      _closed = true;
    }
  }

  void _write(List<PrefixRecord> records) {
    final statement = _database.prepare(
      'INSERT INTO prefixes (id, document) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET document = excluded.document',
    );
    try {
      for (final record in records) {
        statement.execute([record.id, jsonEncode(record.toJson())]);
      }
    } finally {
      statement.dispose();
    }
  }

  void _audit(String action, String summary) {
    _database.execute(
      'INSERT INTO audit_entries (action, summary, at) VALUES (?, ?, ?)',
      [action, summary.trim(), DateTime.now().toUtc().toIso8601String()],
    );
  }

  void _validate(List<PrefixRecord> records) {
    final errors = InventoryRules.validate(records);
    if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
  }

  void _checkDuplicateIds(List<PrefixRecord> records) {
    final ids = <String>{};
    for (final record in records) {
      if (!ids.add(record.id))
        throw FormatException('Duplicate record id: ${record.id}.');
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Inventory is closed.');
  }

  void _transaction(void Function() body) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      body();
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }
}
