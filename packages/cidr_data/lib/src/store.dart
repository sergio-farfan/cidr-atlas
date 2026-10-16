// CIDR Atlas
// SQLite inventory persistence and atomic imports.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cidr_core/cidr_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart' as sqlite_loader;

import 'identity.dart';
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
    if (path.trim().isEmpty) {
      throw ArgumentError('Database path cannot be blank.');
    }
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
        final conflicts = InventoryRules.conflictsFor(
          records.map((record) => record.id).toSet(),
          combined.values.toList(),
        );
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

  /// Deletes one record. A record that other records name as their parent is
  /// refused with an explanation; delete or re-parent the children first.
  void delete(String id) => deleteAll([id]);

  /// Deletes several records in one transaction, validating the remaining
  /// inventory once and writing one audit entry. Unknown ids are ignored, so
  /// children and parents may be listed in any order. A record that a
  /// remaining record names as its parent is refused with an explanation.
  void deleteAll(List<String> ids) {
    _ensureOpen();
    _transaction(() {
      final current = list();
      final byId = {for (final record in current) record.id: record};
      final targets = {
        for (final id in ids)
          if (byId.containsKey(id)) id
      };
      if (targets.isEmpty) return;
      final remaining =
          current.where((record) => !targets.contains(record.id)).toList();
      for (final id in targets) {
        final children =
            remaining.where((record) => record.parentId == id).toList();
        if (children.isNotEmpty) {
          throw FormatException(_childrenMessage(byId[id]!, children));
        }
      }
      _validate(remaining);
      final statement = _database.prepare('DELETE FROM prefixes WHERE id = ?');
      try {
        for (final id in targets) {
          statement.execute([id]);
        }
      } finally {
        statement.dispose();
      }
      _audit(
        'delete',
        targets.length == 1
            ? 'Deleted prefix ${targets.single}.'
            : 'Deleted ${targets.length} prefixes: ${targets.join(', ')}.',
      );
    });
  }

  static String _childrenMessage(
      PrefixRecord parent, List<PrefixRecord> children) {
    const shown = 5;
    final names = [
      for (final child in children.take(shown)) '${child.name} (${child.cidr})',
      if (children.length > shown) 'and ${children.length - shown} more',
    ].join(', ');
    final count = children.length == 1
        ? '1 child prefix references it'
        : '${children.length} child prefixes reference it';
    return 'Cannot delete ${parent.name} (${parent.cidr}): $count: $names. '
        'Delete or re-parent them first.';
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
            .where((existing) => sameOciIdentity(existing, incoming))
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
    // Region spellings replaced by an OCI refresh, by record id.
    final respelled = <String, (String, String)>{};
    for (final incoming in preview.records) {
      final targetId = aliases[incoming.id] ?? incoming.id;
      final existing = current[targetId];
      if (existing != null &&
          ociImport &&
          incoming.source == 'oci' &&
          existing.region.isNotEmpty &&
          incoming.region.isNotEmpty &&
          existing.region != incoming.region) {
        respelled[targetId] = (existing.region, incoming.region);
      }
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
          : existing != null
              ? preview.mergeOnto(existing, normalized)
              : normalized;
      current[record.id] = record;
    }
    if (respelled.isNotEmpty) _respellLinkedRegions(current, respelled);
    if (ociImport) {
      for (final incoming in preview.records) {
        final targetId = aliases[incoming.id] ?? incoming.id;
        final child = current[targetId]!;
        if (child.kind != PrefixKind.subnet ||
            child.parentId.isNotEmpty ||
            child.vcnId.isEmpty) {
          continue;
        }
        final parents = current.values
            .where((candidate) =>
                candidate.kind == PrefixKind.vcn &&
                candidate.resourceId == child.vcnId &&
                candidate.routingDomain == child.routingDomain &&
                sameKnownScope(candidate.tenancy, child.tenancy) &&
                sameKnownScope(candidate.region, child.region) &&
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

  /// Carries a refreshed region spelling across explicit VCN/subnet parent
  /// links. A record matched by OCID may change from a v0.3.0 spelling such
  /// as `IAD` to `us-ashburn-1`; a linked VCN or subnet that this import did
  /// not observe, and that still holds exactly the old spelling, receives the
  /// new one so the link does not appear to cross regions.
  static void _respellLinkedRegions(
    Map<String, PrefixRecord> current,
    Map<String, (String, String)> respelled,
  ) {
    final childrenByParent = <String, List<String>>{};
    for (final record in current.values) {
      if (record.parentId.isNotEmpty) {
        (childrenByParent[record.parentId] ??= []).add(record.id);
      }
    }
    final pending = respelled.entries.toList();
    while (pending.isNotEmpty) {
      final MapEntry(key: id, value: (from, to)) = pending.removeLast();
      final record = current[id];
      if (record == null) continue;
      final linked = <String>[
        if (record.kind == PrefixKind.subnet) record.parentId,
        if (record.kind == PrefixKind.vcn) ...?childrenByParent[id],
      ];
      for (final otherId in linked) {
        final other = current[otherId];
        if (other == null ||
            other.region != from ||
            respelled.containsKey(otherId)) {
          continue;
        }
        final isPair = (record.kind == PrefixKind.subnet &&
                other.kind == PrefixKind.vcn) ||
            (record.kind == PrefixKind.vcn && other.kind == PrefixKind.subnet);
        if (!isPair) continue;
        current[otherId] = other.copyWith(region: to);
        respelled[otherId] = (from, to);
        pending.add(MapEntry(otherId, (from, to)));
      }
    }
  }

  List<AuditEntry> history({int limit = 100}) {
    _ensureOpen();
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be nonnegative.');
    }
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
      if (!ids.add(record.id)) {
        throw FormatException('Duplicate record id: ${record.id}.');
      }
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
    } catch (error, stack) {
      // SQLite rolls back by itself on some failures (for example a full disk,
      // an I/O error or RAISE(ROLLBACK)). An explicit ROLLBACK would then fail
      // and hide the original cause, so roll back only an open transaction and
      // always surface the original error.
      if (!_database.autocommit) {
        try {
          _database.execute('ROLLBACK');
        } catch (_) {}
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}
