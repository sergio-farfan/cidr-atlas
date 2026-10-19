// CIDR Atlas
// Command parsing, inventory workflows, and OCI discovery.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_oci/cidr_oci.dart';

import 'src/export_file.dart';
import 'src/recommendation.dart';
import 'src/routing_domains.dart';

// The default database location is defined once, in cidr_data; the CLI keeps
// exposing the name it published before.
export 'package:cidr_data/cidr_data.dart' show defaultDatabasePath;

const _version = '0.4.1';

/// Runs desktop commands, including asynchronous OCI discovery.
Future<int> runCidrctlAsync(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? environment,
  OciInventoryClient? ociClient,
  OciCancellation? cancellation,
}) async {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  final parser = _parser();
  late ArgResults root;
  Duration? collectionTimeout;
  var database = '';
  try {
    root = parser.parse(arguments);
  } on FormatException {
    return runCidrctl(arguments, out: out, err: err, environment: environment);
  }
  try {
    final command = root.command;
    if (command?.name != 'discover' ||
        (root['help'] as bool) ||
        (root['version'] as bool)) {
      return runCidrctl(arguments,
          out: out, err: err, environment: environment);
    }
    if (command!['help'] as bool) {
      _usage(parser.commands['discover']!, output, command: 'discover');
      return 0;
    }
    if (command.rest.length != 1 || command.rest.single != 'oci') {
      throw const FormatException('Discovery type must be oci.');
    }
    _required(command, 'profile');
    _required(command, 'routing-domain');
    final selectedRegions = _discoveryRegions(command);
    final allRegions = command['all-regions'] as bool;
    if (allRegions && command.wasParsed('region')) {
      throw const FormatException('Use --region or --all-regions, not both.');
    }
    if (!allRegions && selectedRegions.isEmpty) {
      throw const FormatException(
          '--region is required unless --all-regions is set.');
    }
    final allCompartments = command['all-compartments'] as bool;
    if (allCompartments && command.wasParsed('compartment-id')) {
      throw const FormatException(
          'Use --compartment-id or --all-compartments, not both.');
    }
    if (!allCompartments) _required(command, 'compartment-id');
    collectionTimeout = _collectionTimeout(command);
    // Resolve the local database before contacting OCI, so a missing HOME or
    // an unusable path fails fast instead of after a long collection. The
    // store itself opens only after a successful discovery.
    database =
        _databasePath(command, root, environment ?? Platform.environment);
    _checkDatabaseLocation(database, write: command['apply'] as bool);
  } on FormatException catch (error) {
    errors.writeln('Usage error: ${error.message}');
    errors.writeln('Run cidrctl discover oci --help.');
    return 2;
  } on FileSystemException catch (error) {
    errors.writeln('File error: ${error.message} (${error.path ?? database}). '
        'Check --db before discovery.');
    return 1;
  }
  final command = root.command!;
  final token = cancellation ?? OciCancellation();
  StreamSubscription<ProcessSignal>? interrupt;
  InventoryStore? store;
  try {
    _checkCancellation(token);
    interrupt = ProcessSignal.sigint.watch().listen((_) => token.cancel());
    final client =
        ociClient ?? OciCliClient(collectionTimeout: collectionTimeout);
    final auth = switch (command['auth'] as String?) {
      'api_key' => OciAuthMode.apiKey,
      'security_token' => OciAuthMode.securityToken,
      _ => null,
    };
    final connection = await client.connection(
      profile: _required(command, 'profile'),
      configFile: command['config-file'] as String?,
      executable: command['oci-bin'] as String?,
      authMode: auth,
    );
    errors.writeln('Using OCI configuration ${connection.configFile}, '
        'profile ${connection.profile} '
        '(${connection.authMode == OciAuthMode.securityToken ? 'security_token' : 'api_key'} authentication).');
    _checkCancellation(token);
    var scopeAnnounced = false;
    final discovery = await client.discover(
      connection,
      regions: _discoveryRegions(command),
      allRegions: command['all-regions'] as bool,
      compartmentId: (command['all-compartments'] as bool)
          ? null
          : _required(command, 'compartment-id'),
      allCompartments: command['all-compartments'] as bool,
      cancellation: token,
      onDiscoveryProgress: (progress) {
        final count = progress.scopeCount;
        if (!scopeAnnounced && count != null) {
          scopeAnnounced = true;
          // The explicit flag is what the CLI gave its own adapter; otherwise
          // the adapter reports the default for the resolved scope.
          final limit = collectionTimeout ?? progress.collectionTimeout;
          errors.writeln('Collecting $count region/compartment '
              'scope${count == 1 ? '' : 's'} with ${count * 2} sequential '
              'list requests within the ${limit.inSeconds}-second '
              '${collectionTimeout == null ? 'default ' : ''}collection limit.');
        }
        errors.writeln(progress.message);
      },
    );
    _checkCancellation(token);
    final domain = _required(command, 'routing-domain');
    // An empty observation needs no inventory: report it without opening or
    // creating the database, for both preview and --apply.
    final observed =
        InventoryImport.json(discovery.bundleJson, routingDomain: domain);
    if (observed.isEmptyResult) {
      for (final warning in {...discovery.warnings, ...observed.warnings}) {
        output.writeln('Warning: $warning');
      }
      output.writeln('Discovery completed: no networks were found in the '
          'selected scope. No records were changed.');
      return 0;
    }
    final existed = File(database).existsSync();
    store = InventoryStore.open(database);
    if (!existed) _warnCreated(database, errors);
    final existing = store.list();
    warnUnknownRoutingDomain(existing, domain, errors);
    final preview = InventoryImport.json(
      discovery.bundleJson,
      routingDomain: domain,
      existingRecords: existing,
    );
    for (final warning in discovery.warnings) {
      output.writeln('Warning: $warning');
    }
    _checkCancellation(token);
    return _applyPreview(
        store, preview, command['apply'] as bool, output, errors);
  } on OciException catch (error) {
    errors.writeln('Discovery failed: ${error.message}');
    return 1;
  } on FormatException {
    errors.writeln(
        'Discovery returned invalid inventory. No records were changed.');
    return 1;
  } on FileSystemException catch (error) {
    errors.writeln('Discovery could not access a required file'
        '${error.path == null ? '' : ' (${error.path})'}. '
        'Check paths and permissions; the inventory database is $database.');
    return 1;
  } catch (_) {
    errors.writeln(
        'Discovery failed. Check OCI configuration and database access.');
    return 1;
  } finally {
    store?.close();
    await interrupt?.cancel();
  }
}

const _maximumCollectionSeconds = 86400;
const _minimumCollectionSeconds = 30;

Duration? _collectionTimeout(ArgResults command) {
  final raw = (command['collection-timeout'] as String?)?.trim();
  if (raw == null) return null;
  final seconds = RegExp(r'^[0-9]+$').hasMatch(raw) ? int.tryParse(raw) : null;
  if (seconds == null ||
      seconds < _minimumCollectionSeconds ||
      seconds > _maximumCollectionSeconds) {
    throw const FormatException('--collection-timeout must be a whole number '
        'of seconds from $_minimumCollectionSeconds to '
        '$_maximumCollectionSeconds.');
  }
  return Duration(seconds: seconds);
}

/// The command database, global database, or shared default location.
/// Missing environment for the default and a blank path are usage errors.
String _databasePath(
    ArgResults command, ArgResults root, Map<String, String> environment) {
  final explicit = (command['db'] as String?) ?? (root['db'] as String?);
  if (explicit != null) {
    if (explicit.trim().isEmpty) {
      throw const FormatException('--db cannot be blank.');
    }
    return explicit;
  }
  try {
    return defaultDatabasePath(environment);
  } on StateError catch (error) {
    throw FormatException(error.message);
  }
}

/// Checks, without creating anything, that [path] can hold a database file:
/// it is not a directory, its nearest existing ancestor is a directory, and,
/// when [write] is set, an existing file can be opened for writing.
void _checkDatabaseLocation(String path, {required bool write}) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.directory) {
    throw FileSystemException('The database path is a directory', path);
  }
  if (type != FileSystemEntityType.notFound) {
    if (write) File(path).openSync(mode: FileMode.append).closeSync();
    // Opening an existing inventory reads its schema version without writing,
    // so a non-SQLite or newer-schema file fails before any OCI request.
    try {
      InventoryStore.open(path).close();
    } on Object {
      throw FileSystemException(
          'The file cannot be opened as a CIDR Atlas inventory', path);
    }
    return;
  }
  var ancestor = File(path).absolute.parent;
  while (FileSystemEntity.typeSync(ancestor.path) ==
          FileSystemEntityType.notFound &&
      ancestor.parent.path != ancestor.path) {
    ancestor = ancestor.parent;
  }
  if (FileSystemEntity.typeSync(ancestor.path) !=
      FileSystemEntityType.directory) {
    throw FileSystemException(
        'The database location is inside a file, not a directory', path);
  }
}

void _warnCreated(String path, StringSink errors) {
  errors.writeln('Warning: created a new empty inventory at $path. '
      'If you expected existing records, check --db.');
}

void _checkCancellation(OciCancellation cancellation) {
  if (cancellation.isCancelled) {
    throw const OciException('Discovery cancelled. No records were changed.');
  }
}

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
      final misuse =
          command == null && arguments.isNotEmpty && !(root['help'] as bool);
      if (misuse) {
        errors.writeln(root.rest.isEmpty
            ? 'Usage error: a command is required.'
            : 'Usage error: unknown command ${root.rest.first}.');
      }
      _usage(parser, output);
      return misuse ? 2 : 0;
    }
    final commandParser = parser.commands[command.name]!;
    if (command['help'] as bool) {
      _usage(commandParser, output, command: command.name);
      return 0;
    }
    if (command.name == 'discover') {
      throw const FormatException(
          'Discovery requires the asynchronous CLI entrypoint.');
    }
    final db = _databasePath(command, root, env);
    if (command.name == 'clear') return _clear(db, command, output, errors);
    final existed = File(db).existsSync();
    store = InventoryStore.open(db);
    if (!existed) _warnCreated(db, errors);
    switch (command.name) {
      case 'list':
        _requireRest(command, 0);
        final records = _filtered(store.list(), command);
        _writeRecords(records, command['format'] as String, output);
        return 0;
      case 'check':
      case 'reserve':
        _requireRest(command, 1);
        final reserve = command.name == 'reserve';
        final candidate = _candidate(command, reserve);
        final current = store.list();
        if (reserve && current.any((record) => record.id == candidate.id)) {
          _writeDuplicate(candidate, errors);
          return 1;
        }
        // An explicit id can check an edit against all other current records.
        final records =
            current.where((record) => record.id != candidate.id).toList();
        warnUnknownRoutingDomain(records, candidate.routingDomain, errors);
        final combined = [...records, candidate];
        final validation = InventoryRules.validate(combined);
        if (validation.isNotEmpty) {
          for (final issue in validation) {
            errors.writeln(issue);
          }
          return 1;
        }
        // Review notices never change the result or exit code.
        for (final advisory
            in InventoryRules.advisories(combined, involving: {candidate.id})) {
          errors.writeln('Advisory: $advisory');
        }
        final conflicts = InventoryRules.conflictsFor({candidate.id}, combined);
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
        if (reserve) {
          // The store rechecks identity, structure and conflicts inside the
          // write transaction, so a concurrent writer cannot be overwritten.
          try {
            store.reserve(candidate);
          } on InventoryConflictException catch (error) {
            errors.writeln('Reservation was not saved: $error');
            return 3;
          } on FormatException catch (error) {
            if (store.list().any((record) => record.id == candidate.id)) {
              _writeDuplicate(candidate, errors);
            } else {
              errors.writeln('Reservation was not saved: ${error.message}');
            }
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
      case 'recommend':
        return runRecommendation(store, command, output, errors);
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
          if (file.trim().isEmpty) {
            throw const FormatException('--file cannot be blank.');
          }
          checkExportDestination(file, db);
          writeExportAtomically(file, content);
          output.writeln('Exported ${records.length} records to $file.');
        }
        return 0;
      case 'history':
        _requireRest(command, 0);
        final rawLimit = (command['limit'] as String).trim();
        final limit = RegExp(r'^[0-9]+$').hasMatch(rawLimit)
            ? int.tryParse(rawLimit)
            : null;
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
  command('discover')
    ..addOption('profile', help: 'Required OCI configuration profile.')
    ..addMultiOption('region',
        splitCommas: false,
        help:
            'Selected OCI regions, repeatable or comma-separated; exclusive with --all-regions.')
    ..addFlag('all-regions',
        negatable: false, help: 'Collect all READY subscribed regions.')
    ..addOption('compartment-id',
        help:
            'One direct OCI compartment OCID; exclusive with --all-compartments.')
    ..addFlag('all-compartments',
        negatable: false,
        help:
            'Collect tenancy root and all accessible active compartments/subcompartments.')
    ..addOption('routing-domain', help: 'Required conflict-checking scope.')
    ..addOption('config-file', help: 'OCI configuration file override.')
    ..addOption('oci-bin', help: 'OCI executable path override.')
    ..addOption('auth',
        allowed: ['api_key', 'security_token'],
        help: 'Authentication override; otherwise use profile authentication.')
    ..addOption('collection-timeout',
        valueHelp: 'seconds',
        help: 'Whole-discovery time limit, $_minimumCollectionSeconds to '
            '$_maximumCollectionSeconds seconds. Default: '
            '${OciCollectionLimits.singleScope.inSeconds} for one region and '
            'compartment, ${OciCollectionLimits.broadScope.inSeconds} for '
            'broader scopes.')
    ..addFlag('apply',
        negatable: false,
        help: 'Write after successful discovery and import validation.');
  final exporting = command('export');
  filters(exporting);
  exporting
    ..addOption('format', allowed: ['csv', 'json'], defaultsTo: 'json')
    ..addOption('file', help: 'Destination file; stdout when omitted.');
  command('history')
    ..addOption('limit', defaultsTo: '50')
    ..addOption('format', allowed: ['table', 'json'], defaultsTo: 'table');
  addRecommendationOptions(command('recommend'));
  command('clear')
    ..addOption('routing-domain',
        help: 'Clear only this exact routing domain; otherwise everything.')
    ..addFlag('yes',
        negatable: false,
        help: 'Required confirmation that local records are deleted.');
  return parser;
}

void _usage(ArgParser parser, StringSink output, {String? command}) {
  if (command == null) {
    output.writeln('CIDR Atlas command line interface $_version');
    output.writeln('Usage: cidrctl [--db PATH] <command> [options]');
    output.writeln('Commands: list, check <CIDR>, reserve <CIDR>, '
        'recommend, import [csv|json|oci], discover oci, export, history, '
        'clear');
  } else {
    output.writeln('Usage: cidrctl $command '
        '${command == 'check' || command == 'reserve' ? '<CIDR> ' : ''}'
        '${command == 'import' ? '[csv|json|oci] ' : ''}'
        '${command == 'discover' ? 'oci ' : ''}[options]');
  }
  output.writeln(parser.usage);
  output.writeln();
  output.writeln(switch (command) {
    'discover' =>
      '''No manual CIDR is required: OCI supplies existing VCN/subnet CIDRs.
Choose an existing profile and routing domain, then one option per scope dimension:
  --region NAME (repeatable or comma-separated) OR --all-regions
  --compartment-id OCID OR --all-compartments
--all-regions freshly selects READY subscribed regions; other statuses are excluded.
--all-compartments includes tenancy root and all accessible active descendants.
A selected parent is direct-only: it does not collect child compartment resources.
Examples (fictional scopes; preview only):
  cidrctl discover oci --profile EXAMPLE --region us-phoenix-1 --compartment-id ocid1.compartment.oc1..example --routing-domain fictional-connected
  cidrctl discover oci --profile EXAMPLE --region us-phoenix-1,eu-frankfurt-1 --all-compartments --routing-domain fictional-connected
  cidrctl discover oci --profile EXAMPLE --all-regions --compartment-id ocid1.compartment.oc1..example --routing-domain fictional-connected
  cidrctl discover oci --profile EXAMPLE --all-regions --all-compartments --routing-domain fictional-connected
Accessible compartment visibility does not grant network-list permission or expose IAM-hidden scopes.
Any failed required enumeration/list returns no applicable partial inventory.
Without --config-file, OCI_CLI_CONFIG_FILE (when set) or ~/.oci/config is used.
Progress on stderr names the OCI configuration file and profile used, then the
region/compartment scope count once enumeration finishes. A large broad scope
can exceed the default limit; raise it with --collection-timeout SECONDS.
An empty result exits 0 with nothing to apply; review profile, regions, scope and IAM permissions.
One combined preview precedes atomic apply. Absent records are retained; omissions do not prove free IPs.
Add --apply only after reviewing the intended scope and preview.''',
    'import' =>
      '''Reads CIDRs from the file; do not enter a manual CIDR for import.
CSV and Atlas backups retain their routing domains. OCI JSON requires a domain.
Example (preview only):
  cidrctl import csv --file examples/fictional_inventory.csv
  cidrctl import oci --file examples/fictional_oci_bundle.json --routing-domain fictional-connected
Use --routing-domain only for OCI JSON; it is rejected for CSV and Atlas backups.
Apply requires a nonempty valid preview. An empty file has nothing to save.
Add --apply only after review; absent existing records are retained.''',
    'recommend' =>
      '''The pool is the boundary to search; the prefix is the requested new size.
Use --parent ID when selecting an existing inventory pool.
Examples (fictional boundary; preview only):
  cidrctl recommend --pool 10.64.0.0/16 --routing-domain fictional-connected --prefix 24
  cidrctl recommend --pool 10.64.0.0/16 --routing-domain fictional-connected --addresses 100 --growth-percent 20 --additional 4 --policy oci_ipv4 --kind subnet
The second example needs 124 assignable addresses and selects an OCI /25 (125 assignable).
Use --basis peak for an already planned peak and explicitly choose growth, including zero.
Availability is limited to this inventory/domain. Review coverage before reserving.
Add --apply --name NAME to reserve the first ranked candidate locally.''',
    'check' ||
    'reserve' =>
      '''Enter a full canonical network CIDR, for example 10.64.0.0/24.
A /24 has 256 total IPv4 addresses; provider assignable capacity is separate.
Use the same routing-domain name for connected networks and --parent ID for approved containment.
Example:
  cidrctl check 10.64.0.0/24 --routing-domain fictional-connected
  cidrctl reserve 10.64.0.0/24 --name fictional-subnet --kind subnet --routing-domain fictional-connected
Reserve saves a new local record and refuses an existing id; it does not provision an OCI network.
A routing domain with no existing records prints a warning naming the known domains.''',
    'clear' =>
      '''Deletes local inventory records in one transaction; OCI resources are not changed.
Without --routing-domain every local record is removed; with it, only that domain.
--yes is required. Export a copy first, then clear (fictional domain):
  cidrctl export --file fictional-backup.json
  cidrctl clear --routing-domain fictional-connected --yes
  cidrctl clear --yes
History keeps one delete entry. Clear never creates an inventory: a missing --db fails.
A record in another domain that names a cleared record as its parent blocks the clear.''',
    null => '''When is a prefix needed?
  discover/import: CIDRs come from OCI or the inventory file.
  check/reserve: enter a full CIDR such as 10.64.0.0/24.
  recommend: select a pool, then --prefix 24 or --addresses with explicit growth.
Use cidrctl <command> --help for guidance and fictional examples.
Use --db PATH for a separate local inventory. Imports/recommendations preview by default.
A command that creates a new empty inventory file warns on stderr; check --db if unexpected.
Export --file replaces an ordinary existing file but refuses the open inventory database.
Clear deletes local records only and requires --yes; export a copy first.''',
    _ => 'Use cidrctl --help to choose a workflow.',
  });
}

List<String> _discoveryRegions(ArgResults command) {
  final selected = <String>{};
  for (final argument in command['region'] as List<String>) {
    for (final value in argument.split(',')) {
      final region = value.trim();
      if (region.isEmpty) {
        throw const FormatException(
            '--region must contain nonblank region names.');
      }
      selected.add(region);
    }
  }
  return selected.toList();
}

/// Deletes every local record, or every record in one routing domain, in a
/// single validated transaction. Never creates an inventory file.
int _clear(
    String db, ArgResults command, StringSink output, StringSink errors) {
  _requireRest(command, 0);
  final domain = (command['routing-domain'] as String?)?.trim();
  if (domain != null && domain.isEmpty) {
    throw const FormatException('--routing-domain cannot be blank.');
  }
  if (!(command['yes'] as bool)) {
    throw const FormatException('clear deletes local inventory records and '
        'requires --yes. OCI resources are not changed. Run '
        '"cidrctl export --file BACKUP.json" first to keep a copy.');
  }
  switch (FileSystemEntity.typeSync(db)) {
    case FileSystemEntityType.notFound:
      errors.writeln('Inventory not found: $db. Clear never creates an '
          'inventory; check --db.');
      return 1;
    case FileSystemEntityType.directory:
      throw FileSystemException('The database path is a directory', db);
    default:
      break;
  }
  final store = InventoryStore.open(db);
  try {
    final records = store.list();
    final selected = domain == null
        ? records
        : records
            .where((record) => record.routingDomain.trim() == domain)
            .toList();
    if (selected.isEmpty) {
      if (domain != null) warnUnknownRoutingDomain(records, domain, errors);
      output.writeln('No records to clear.');
      return 0;
    }
    try {
      store.deleteAll([for (final record in selected) record.id]);
    } on FormatException catch (error) {
      errors.writeln('Clear was not saved: ${error.message}');
      return 1;
    }
    final count =
        selected.length == 1 ? '1 record' : '${selected.length} records';
    output.writeln(domain == null
        ? 'Cleared $count from the local inventory. '
            'OCI resources were not changed.'
        : 'Cleared $count from routing domain $domain. '
            'OCI resources were not changed.');
    return 0;
  } finally {
    store.close();
  }
}

void _requireRest(ArgResults command, int count) {
  if (command.rest.length != count) {
    throw FormatException('$count positional argument(s) required for '
        '${command.name}.');
  }
}

void _writeDuplicate(PrefixRecord candidate, StringSink errors) {
  errors.writeln('A record with id ${candidate.id} already exists. '
      'Reserve creates new records; use the app to edit it.');
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
  final json = type == 'csv' ? null : _jsonObject(source);
  final backupContent = json != null && _isBackup(json);
  final ociContent = json != null && !backupContent;
  if (command.wasParsed('routing-domain') && (type == 'csv' || backupContent)) {
    throw const FormatException('--routing-domain applies only to OCI JSON '
        'imports; CSV rows and Atlas backups keep their own routing domains.');
  }
  if ((type == 'oci' || ociContent) && domain.trim().isEmpty) {
    throw const FormatException(
        '--routing-domain is required for OCI imports.');
  }
  final existing = store.list();
  if (ociContent) warnUnknownRoutingDomain(existing, domain, errors);
  final preview = type == 'csv'
      ? InventoryImport.csv(source, existingRecords: existing)
      : InventoryImport.json(source,
          routingDomain: domain, existingRecords: existing);
  return _applyPreview(
      store, preview, command['apply'] as bool, output, errors);
}

/// The decoded JSON object, or null when [source] is not a JSON object; the
/// import itself reports malformed input.
Map<String, dynamic>? _jsonObject(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// Mirrors the backup detection in [InventoryImport.json].
bool _isBackup(Map<String, dynamic> root) =>
    root.containsKey('format') ||
    root.containsKey('records') ||
    root.containsKey('version');

int _applyPreview(InventoryStore store, ImportPreview preview, bool apply,
    StringSink output, StringSink errors) {
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
  if (!apply) {
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
