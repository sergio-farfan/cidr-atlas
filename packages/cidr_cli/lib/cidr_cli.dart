library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';

const _version = '0.1.0';

/// Runs a command without terminating the host process.
///
/// Exit codes: 0 success, 1 operation or import validation failure, 2 invalid
/// command usage, and 3 conflicting address space. Imports may deliberately
/// retain conflicts for review, but reserve never writes a conflicting record.
int runCidrctl(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? environment,
}) {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  final env = environment ?? Platform.environment;
  final parser = _parser();
  InventoryStore? store;
  try {
    final root = parser.parse(arguments);
    if (root['version'] as bool) {
      output.writeln('cidrctl $_version');
      return 0;
    }
    final command = root.command;
    if ((root['help'] as bool) || command == null) {
      _usage(parser, output);
      return command == null && arguments.isNotEmpty && !(root['help'] as bool)
          ? 2
          : 0;
    }
    final commandParser = parser.commands[command.name]!;
    if (command['help'] as bool) {
      _usage(commandParser, output, command: command.name);
      return 0;
    }
    final db = (command['db'] as String?) ??
        (root['db'] as String?) ??
        defaultDatabasePath(env);
    store = InventoryStore.open(db);
    switch (command.name) {
      case 'list':
        _requireRest(command, 0);
        final records = _filtered(store.list(), command);
        _writeRecords(records, command['format'] as String, output);
        return 0;
      case 'check':
      case 'reserve':
        _requireRest(command, 1);
        final candidate = _candidate(command, command.name == 'reserve');
        // An explicit id can check an edit against all other current records.
        final records =
            store.list().where((record) => record.id != candidate.id).toList();
        final combined = [...records, candidate];
        final validation = InventoryRules.validate(combined);
        if (validation.isNotEmpty) {
          for (final issue in validation) {
            errors.writeln(issue);
          }
          return 1;
        }
        final conflicts = InventoryRules.conflicts(combined)
            .where((conflict) =>
                conflict.first.id == candidate.id ||
                conflict.second.id == candidate.id)
            .toList();
        if (conflicts.isNotEmpty) {
          output.writeln('Conflicts for ${candidate.cidr} in '
              '${candidate.routingDomain}:');
          for (final conflict in conflicts) {
            final other = conflict.first.id == candidate.id
                ? conflict.second
                : conflict.first;
            output.writeln('  ${other.cidr}  ${other.name} '
                '[${other.id}]: ${conflict.reason}');
          }
          return 3;
        }
        if (command.name == 'reserve') {
          if (store.list().any((record) => record.id == candidate.id)) {
            errors.writeln('A record with id ${candidate.id} already exists. '
                'Reserve creates new records; use the app to edit it.');
            return 1;
          }
          try {
            store.save(candidate, rejectConflicts: true);
          } on InventoryConflictException catch (error) {
            errors.writeln('Reservation was not saved: $error');
            return 3;
          } on FormatException catch (error) {
            errors.writeln('Reservation was not saved: ${error.message}');
            return 1;
          }
          output.writeln('Reserved ${candidate.cidr} as ${candidate.name} '
              '[${candidate.id}] in ${candidate.routingDomain}.');
        } else {
          output.writeln('No conflicts: ${candidate.cidr} in '
              '${candidate.routingDomain}.');
        }
        return 0;
      case 'import':
        return _import(store, command, output, errors);
      case 'export':
        _requireRest(command, 0);
        final format = command['format'] as String;
        final allRecords = store.list();
        final records =
            _withAncestors(_filtered(allRecords, command), allRecords);
        final content = format == 'csv'
            ? InventoryImport.exportCsv(records)
            : InventoryImport.exportJson(records);
        final file = command['file'] as String?;
        if (file == null) {
          output.writeln(content);
        } else {
          File(file).writeAsStringSync(content);
          output.writeln('Exported ${records.length} records to $file.');
        }
        return 0;
      case 'history':
        _requireRest(command, 0);
        final limit = int.tryParse(command['limit'] as String);
        if (limit == null || limit < 1) {
          throw const FormatException('--limit must be a positive integer.');
        }
        final entries = store.history(limit: limit);
        if (command['format'] == 'json') {
          output.writeln(const JsonEncoder.withIndent('  ').convert([
            for (final entry in entries)
              {
                'at': entry.at.toUtc().toIso8601String(),
                'action': entry.action,
                'summary': entry.summary,
              },
          ]));
        } else if (entries.isEmpty) {
          output.writeln('No history yet.');
        } else {
          for (final entry in entries) {
            output.writeln('${entry.at.toUtc().toIso8601String()} '
                '${entry.action}  ${entry.summary}');
          }
        }
        return 0;
      default:
        throw FormatException('Unknown command: ${command.name}');
    }
  } on FormatException catch (error) {
    errors.writeln('Usage error: ${error.message}');
    errors.writeln('Run cidrctl --help or cidrctl <command> --help.');
    return 2;
  } on FileSystemException catch (error) {
    errors.writeln('File error: ${error.message}'
        '${error.path == null ? '' : ' (${error.path})'}');
    return 1;
  } catch (error) {
    errors.writeln('Operation failed: $error');
    return 1;
  } finally {
    store?.close();
  }
}

/// Uses the same support-directory layout as the graphical application.
String defaultDatabasePath(Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (Platform.isMacOS) {
    if (home == null) throw StateError('HOME is not set; specify --db.');
    return '$home/Library/Application Support/cidr_atlas/inventory.sqlite';
  }
  if (Platform.isWindows) {
    final appData = environment['APPDATA'];
    if (appData == null) throw StateError('APPDATA is not set; specify --db.');
    return '$appData/cidr_atlas/inventory.sqlite';
  }
  final dataHome = environment['XDG_DATA_HOME'];
  if (dataHome != null && dataHome.isNotEmpty) {
    return '$dataHome/cidr_atlas/inventory.sqlite';
  }
  if (home == null) throw StateError('HOME is not set; specify --db.');
  return '$home/.local/share/cidr_atlas/inventory.sqlite';
}

ArgParser _parser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.')
    ..addFlag('version', negatable: false, help: 'Show the CLI version.')
    ..addOption('db', help: 'SQLite file path. Default: application support.');
  ArgParser command(String name) {
    final sub = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.')
      ..addOption('db', help: 'SQLite file path (overrides global --db).');
    parser.addCommand(name, sub);
    return sub;
  }

  void filters(ArgParser sub) {
    sub
      ..addOption('routing-domain', help: 'Exact routing domain.')
      ..addOption('region', help: 'Exact OCI region.')
      ..addOption('customer', help: 'Exact customer.')
      ..addOption('status', allowed: PrefixStatus.values.map((e) => e.name));
  }

  final listing = command('list');
  filters(listing);
  listing.addOption('format',
      allowed: ['table', 'json', 'csv'], defaultsTo: 'table');
  for (final name in ['check', 'reserve']) {
    command(name)
      ..addOption('routing-domain', help: 'Required conflict-checking scope.')
      ..addOption('name', help: 'Record name (required for reserve).')
      ..addOption('id', help: 'Record id; check can use an existing id.')
      ..addOption('parent', help: 'Explicit parent record id.')
      ..addOption('kind',
          allowed: PrefixKind.values.map((e) => e.name), defaultsTo: 'vcn')
      ..addOption('customer')
      ..addOption('tenancy')
      ..addOption('region')
      ..addOption('compartment')
      ..addOption('environment')
      ..addOption('owner')
      ..addOption('notes')
      ..addOption('resource-id')
      ..addOption('vcn-id');
  }
  command('import')
    ..addOption('file', help: 'Required input file path.')
    ..addOption('routing-domain', help: 'Required for OCI JSON imports.')
    ..addFlag('apply',
        negatable: false,
        help: 'Write the preview after successful validation.');
  final exporting = command('export');
  filters(exporting);
  exporting
    ..addOption('format', allowed: ['csv', 'json'], defaultsTo: 'json')
    ..addOption('file', help: 'Destination file; stdout when omitted.');
  command('history')
    ..addOption('limit', defaultsTo: '50')
    ..addOption('format', allowed: ['table', 'json'], defaultsTo: 'table');
  return parser;
}

void _usage(ArgParser parser, StringSink output, {String? command}) {
  if (command == null) {
    output.writeln('CIDR Atlas command line interface $_version');
    output.writeln('Usage: cidrctl [--db PATH] <command> [options]');
    output.writeln('Commands: list, check <CIDR>, reserve <CIDR>, '
        'import [csv|json|oci], export, history');
  } else {
    output.writeln('Usage: cidrctl $command '
        '${command == 'check' || command == 'reserve' ? '<CIDR> ' : ''}'
        '${command == 'import' ? '[csv|json|oci] ' : ''}[options]');
  }
  output.writeln(parser.usage);
}

void _requireRest(ArgResults command, int count) {
  if (command.rest.length != count) {
    throw FormatException('$count positional argument(s) required for '
        '${command.name}.');
  }
}

String _required(ArgResults command, String key) {
  final value = command[key] as String?;
  if (value == null || value.trim().isEmpty) {
    throw FormatException('--$key is required.');
  }
  return value.trim();
}

PrefixRecord _candidate(ArgResults command, bool reserve) {
  final cidr = Cidr.parse(command.rest.single);
  final domain = _required(command, 'routing-domain');
  final name = reserve
      ? _required(command, 'name')
      : ((command['name'] as String?) ?? 'CIDR check');
  return PrefixRecord(
    id: (command['id'] as String?) ??
        (reserve
            ? 'local-${DateTime.now().microsecondsSinceEpoch}'
            : '__cidr_atlas_check__'),
    cidr: cidr.canonical,
    name: name,
    routingDomain: domain,
    kind: PrefixKind.values.byName(command['kind'] as String),
    status: PrefixStatus.reserved,
    parentId: (command['parent'] as String?) ?? '',
    customer: (command['customer'] as String?) ?? '',
    tenancy: (command['tenancy'] as String?) ?? '',
    region: (command['region'] as String?) ?? '',
    compartment: (command['compartment'] as String?) ?? '',
    environment: (command['environment'] as String?) ?? '',
    owner: (command['owner'] as String?) ?? '',
    notes: (command['notes'] as String?) ?? '',
    resourceId: (command['resource-id'] as String?) ?? '',
    vcnId: (command['vcn-id'] as String?) ?? '',
    source: 'manual',
  );
}

List<PrefixRecord> _filtered(List<PrefixRecord> records, ArgResults command) {
  return records.where((record) {
    final domain = command['routing-domain'] as String?;
    final region = command['region'] as String?;
    final customer = command['customer'] as String?;
    final status = command['status'] as String?;
    return (domain == null || record.routingDomain == domain) &&
        (region == null || record.region == region) &&
        (customer == null || record.customer == customer) &&
        (status == null || record.status.name == status);
  }).toList();
}

/// A filtered export retains enough parent context to import into a fresh file.
List<PrefixRecord> _withAncestors(
    List<PrefixRecord> selected, List<PrefixRecord> inventory) {
  final included = {for (final record in selected) record.id};
  final byId = {for (final record in inventory) record.id: record};
  final pending = [...selected];
  while (pending.isNotEmpty) {
    final record = pending.removeLast();
    final parent = byId[record.parentId];
    if (parent != null && included.add(parent.id)) pending.add(parent);
    if (record.kind == PrefixKind.subnet && record.vcnId.isNotEmpty) {
      for (final vcn in inventory) {
        if (vcn.kind == PrefixKind.vcn &&
            vcn.resourceId == record.vcnId &&
            vcn.routingDomain == record.routingDomain &&
            vcn.tenancy == record.tenancy &&
            vcn.region == record.region &&
            Cidr.parse(vcn.cidr).contains(Cidr.parse(record.cidr)) &&
            included.add(vcn.id)) {
          pending.add(vcn);
        }
      }
    }
  }
  return inventory.where((record) => included.contains(record.id)).toList();
}

void _writeRecords(
    List<PrefixRecord> records, String format, StringSink output) {
  if (format == 'json') {
    output.writeln(InventoryImport.exportJson(records));
  } else if (format == 'csv') {
    output.writeln(InventoryImport.exportCsv(records));
  } else if (records.isEmpty) {
    output.writeln('No prefixes found.');
  } else {
    output.writeln('CIDR                         KIND        STATUS     '
        'ROUTING DOMAIN       NAME / ID');
    for (final record in records) {
      output.writeln('${record.cidr.padRight(28)} '
          '${record.kind.name.padRight(11)} '
          '${record.status.name.padRight(10)} '
          '${record.routingDomain.padRight(20)} '
          '${record.name} [${record.id}]');
    }
  }
}

int _import(InventoryStore store, ArgResults command, StringSink output,
    StringSink errors) {
  if (command.rest.length > 1 ||
      (command.rest.isNotEmpty &&
          !['csv', 'json', 'oci'].contains(command.rest.single))) {
    throw const FormatException('Import type must be csv, json, or oci.');
  }
  final path = _required(command, 'file');
  final type = command.rest.isEmpty
      ? (path.toLowerCase().endsWith('.csv') ? 'csv' : 'json')
      : command.rest.single;
  final source = File(path).readAsStringSync();
  final domain = (command['routing-domain'] as String?) ?? '';
  if (type == 'oci' && domain.trim().isEmpty) {
    throw const FormatException(
        '--routing-domain is required for OCI imports.');
  }
  final existing = store.list();
  final preview = type == 'csv'
      ? InventoryImport.csv(source, existingRecords: existing)
      : InventoryImport.json(source,
          routingDomain: domain, existingRecords: existing);
  output.writeln('Import preview: ${preview.records.length} records '
      '(${preview.source}).');
  for (final warning in preview.warnings) {
    output.writeln('Warning: $warning');
  }
  for (final issue in preview.errors) {
    errors.writeln('Error: $issue');
  }
  if (!preview.canApply) {
    errors.writeln('Import cannot be applied. No records were changed.');
    return 1;
  }
  late List<PrefixRecord> merged;
  try {
    merged = store.mergedImportRecords(preview);
  } on FormatException catch (error) {
    errors.writeln('Merged inventory is invalid: ${error.message}');
    errors.writeln('No records were changed.');
    return 1;
  }
  final conflicts = InventoryRules.conflicts(merged);
  if (conflicts.isNotEmpty) {
    output.writeln('Warning: merged inventory has ${conflicts.length} '
        'conflict(s). Imported conflicts remain available for review.');
  }
  if (!(command['apply'] as bool)) {
    output.writeln('Preview only. Add --apply to save these records.');
    return 0;
  }
  try {
    store.applyImport(preview);
  } on FormatException catch (error) {
    errors.writeln('Import failed: ${error.message}');
    return 1;
  }
  output.writeln('Applied ${preview.records.length} records. '
      'Absent resources were not removed or retired.');
  return 0;
}
