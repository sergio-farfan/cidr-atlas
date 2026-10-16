// CIDR Atlas
// Command-line safety tests: export destinations, reservations, warnings,
// usage-error consistency, default database location and version.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'package:cidr_cli/cidr_cli.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

const _pool = PrefixRecord(
  id: 'example-pool',
  cidr: '10.64.0.0/16',
  name: 'Fictional pool',
  routingDomain: 'example-corporate',
  kind: PrefixKind.allocation,
);
const _vcn = PrefixRecord(
  id: 'example-vcn',
  cidr: '10.64.0.0/20',
  name: 'Fictional VCN',
  routingDomain: 'example-corporate',
  parentId: 'example-pool',
  status: PrefixStatus.active,
);
const _subnet = PrefixRecord(
  id: 'example-subnet',
  cidr: '10.64.1.0/24',
  name: 'Fictional subnet',
  routingDomain: 'example-corporate',
  kind: PrefixKind.subnet,
  parentId: 'example-vcn',
  status: PrefixStatus.active,
);

void main() {
  late Directory temporary;
  late String database;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('cidr_cli_safety_');
    database = '${temporary.path}/inventory.sqlite';
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  ({int code, String output, String error}) run(List<String> args,
      {String? db, Map<String, String>? environment}) {
    final output = StringBuffer();
    final error = StringBuffer();
    final code = runCidrctl([
      if (environment == null) ...['--db', db ?? database],
      ...args
    ], out: output, err: error, environment: environment);
    return (code: code, output: '$output', error: '$error');
  }

  void seed(List<PrefixRecord> records) {
    final store = InventoryStore.open(database);
    try {
      store.saveAll(records);
    } finally {
      store.close();
    }
  }

  ({List<PrefixRecord> records, List<AuditEntry> history}) snapshot() {
    final store = InventoryStore.open(database);
    try {
      return (records: store.list(), history: store.history());
    } finally {
      store.close();
    }
  }

  group('export destination', () {
    test('refuses the open database and keeps it readable', () {
      seed([_pool, _vcn, _subnet]);
      final before = File(database).readAsBytesSync();
      for (final destination in [
        database,
        '${temporary.path}/./inventory.sqlite',
        '${temporary.path}/sub/../inventory.sqlite',
      ]) {
        Directory('${temporary.path}/sub').createSync(recursive: true);
        final result = run(['export', '--file', destination]);
        expect(result.code, 2, reason: destination);
        expect(result.error, contains('open inventory database'));
        expect(result.output, isNot(contains('Exported')));
      }
      expect(File(database).readAsBytesSync(), before);
      final listing = run(['list']);
      expect(listing.code, 0, reason: listing.error);
      expect(listing.output, contains('example-subnet'));
    });

    test('refuses SQLite companion files without creating them', () {
      seed([_pool]);
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final result = run(['export', '--file', '$database$suffix']);
        expect(result.code, 2, reason: suffix);
        expect(File('$database$suffix').existsSync(), isFalse);
      }
      expect(snapshot().records.single.id, 'example-pool');
    });

    test('refuses companion files reached through a dot-dot segment', () {
      seed([_pool]);
      Directory('${temporary.path}/sub').createSync(recursive: true);
      for (final directory in ['sub', 'missing']) {
        for (final suffix in ['-wal', '-shm', '-journal']) {
          final destination =
              '${temporary.path}/$directory/../inventory.sqlite$suffix';
          final result = run(['export', '--file', destination]);
          expect(result.code, 2, reason: destination);
          expect(File('$database$suffix').existsSync(), isFalse,
              reason: destination);
        }
      }
      expect(snapshot().records.single.id, 'example-pool');
    });

    test('refuses a symbolic link to the database', () {
      seed([_pool]);
      final link = Link('${temporary.path}/alias.sqlite')..createSync(database);
      final result = run(['export', '--file', link.path]);
      expect(result.code, 2);
      expect(snapshot().records.single.id, 'example-pool');
    });

    test('database opened through a link still refuses its real file', () {
      seed([_pool]);
      final link = Link('${temporary.path}/alias.sqlite')..createSync(database);
      final result = run(['export', '--file', database], db: link.path);
      expect(result.code, 2);
      expect(snapshot().records.single.id, 'example-pool');
    });

    test('replaces an ordinary existing file atomically', () {
      seed([_pool, _vcn]);
      final destination = File('${temporary.path}/backup.json')
        ..writeAsStringSync('earlier backup');
      final result = run(['export', '--file', destination.path]);
      expect(result.code, 0, reason: result.error);
      final preview = InventoryImport.json(destination.readAsStringSync(),
          routingDomain: '');
      expect(preview.records.map((record) => record.id),
          ['example-pool', 'example-vcn']);
      expect(temporary.listSync().map((entry) => entry.path),
          everyElement(isNot(contains('.tmp-'))));
    });

    test('replacing an existing export keeps its permission mode', () {
      seed([_pool]);
      final destination = File('${temporary.path}/restricted.json')
        ..writeAsStringSync('earlier backup');
      // Process.runSync passes arguments directly; no shell is involved.
      final chmod = Process.runSync('chmod', ['600', destination.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
      final before = destination.statSync().modeString();
      expect(before, 'rw-------');
      final result = run(['export', '--file', destination.path]);
      expect(result.code, 0, reason: result.error);
      expect(destination.statSync().modeString(), before);
      expect(destination.readAsStringSync(), contains('example-pool'));
    }, testOn: '!windows');

    test('a dangling link destination is followed and its target created', () {
      seed([_pool]);
      Directory('${temporary.path}/exports').createSync();
      // A relative target resolves against the link's own directory.
      final link = Link('${temporary.path}/latest.json')
        ..createSync('exports/backup.json');
      final result = run(['export', '--file', link.path]);
      expect(result.code, 0, reason: result.error);
      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      final target = File('${temporary.path}/exports/backup.json');
      expect(target.readAsStringSync(), contains('example-pool'));
      expect(File(link.path).readAsStringSync(), target.readAsStringSync());
    });

    test('a dangling link to a database companion file is refused', () {
      seed([_pool]);
      final wal = File('$database-wal');
      if (wal.existsSync()) wal.deleteSync();
      final link = Link('${temporary.path}/wal.json')
        ..createSync('$database-wal');
      final result = run(['export', '--file', link.path]);
      expect(result.code, 2);
      expect(result.error, contains('open inventory database'));
      expect(wal.existsSync(), isFalse);
    });

    test('a symbolic link loop fails with a file error', () {
      seed([_pool]);
      Link('${temporary.path}/loop-a.json')
          .createSync('${temporary.path}/loop-b.json');
      Link('${temporary.path}/loop-b.json')
          .createSync('${temporary.path}/loop-a.json');
      final result = run(['export', '--file', '${temporary.path}/loop-a.json']);
      expect(result.code, 1);
      expect(result.error, contains('symbolic links'));
    });

    test('a failed rename onto a directory leaves no temporary file', () {
      seed([_pool]);
      final directory = Directory('${temporary.path}/backup.json')
        ..createSync();
      final result = run(['export', '--file', directory.path]);
      expect(result.code, 1);
      expect(directory.existsSync(), isTrue);
      expect(temporary.listSync().map((entry) => entry.path),
          everyElement(isNot(contains('.tmp-'))));
    });

    test('a failed write leaves an existing export byte-for-byte unchanged',
        () {
      final uid = Process.runSync('id', ['-u']);
      if ('${uid.stdout}'.trim() == '0') {
        markTestSkipped('root can write into a read-only directory');
        return;
      }
      seed([_pool]);
      final exports = Directory('${temporary.path}/exports')..createSync();
      final destination = File('${exports.path}/backup.json')
        ..writeAsBytesSync(utf8.encode('{"earlier": "export"}\n'));
      final before = destination.readAsBytesSync();
      // Process.runSync passes arguments directly; no shell is involved.
      final chmod = Process.runSync('chmod', ['500', exports.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
      try {
        final result = run(['export', '--file', destination.path]);
        expect(result.code, 1, reason: result.error);
        expect(destination.readAsBytesSync(), before);
        expect(
            exports.listSync().map((entry) => entry.path), [destination.path]);
      } finally {
        Process.runSync('chmod', ['700', exports.path]);
      }
    }, testOn: '!windows');
  });

  group('reserve', () {
    test('check and reserve report a placeholder-parent advisory on stderr',
        () {
      seed([
        const PrefixRecord(
          id: 'placeholder-vcn',
          cidr: '10.70.0.0/16',
          name: 'Planned VCN',
          routingDomain: 'example-corporate',
        ),
        const PrefixRecord(
          id: 'observed-vcn',
          cidr: '10.71.0.0/16',
          name: 'Observed VCN',
          routingDomain: 'example-corporate',
          resourceId: 'ocid1.vcn.oc1..fictional',
          status: PrefixStatus.active,
        ),
      ]);
      const subnet = [
        '10.70.1.0/24',
        '--name',
        'Planned subnet',
        '--routing-domain',
        'example-corporate',
        '--kind',
        'subnet',
        '--parent',
        'placeholder-vcn',
        '--vcn-id',
        'ocid1.vcn.oc1..fictional',
      ];
      for (final command in ['check', 'reserve']) {
        final result = run([command, ...subnet, '--id', 'planned-subnet']);
        expect(result.code, 0, reason: result.error);
        expect(
          result.error,
          contains('Advisory: Subnet Planned subnet (10.70.1.0/24) has vcnId '
              'ocid1.vcn.oc1..fictional, which names VCN Observed VCN '
              '(10.71.0.0/16, ocid1.vcn.oc1..fictional), but its parent is the '
              'placeholder VCN Planned VCN (10.70.0.0/16)'),
        );
        expect(result.output, isNot(contains('Advisory')));
      }
      expect(snapshot().records.map((record) => record.id),
          contains('planned-subnet'));
      // An unrelated candidate does not repeat the existing advisory.
      final unrelated = run([
        'check',
        '10.72.0.0/16',
        '--routing-domain',
        'example-corporate',
      ]);
      expect(unrelated.code, 0, reason: unrelated.error);
      expect(unrelated.error, isNot(contains('Advisory')));
    });

    test('records the reserve audit action', () {
      final result = run([
        'reserve',
        '10.42.0.0/20',
        '--name',
        'Fictional reservation',
        '--routing-domain',
        'example-corporate',
        '--id',
        'fictional-reservation',
      ]);
      expect(result.code, 0, reason: result.error);
      expect(snapshot().history.first.action, 'reserve');
    });

    test('an existing id with children is a duplicate, not a structure error',
        () {
      seed([_pool, _vcn, _subnet]);
      final before = snapshot();
      for (final args in [
        ['10.99.0.0/24', '--id', 'example-vcn'],
        ['10.64.0.0/24', '--id', 'example-pool'],
      ]) {
        final result = run([
          'reserve',
          ...args,
          '--name',
          'Fictional duplicate',
          '--routing-domain',
          'example-corporate',
        ]);
        expect(result.code, 1, reason: result.error);
        expect(result.error, contains('already exists'));
        expect(result.error, isNot(contains('cannot be a parent')));
        expect(result.error, isNot(contains('not contained')));
      }
      final after = snapshot();
      expect(after.records.map((record) => record.toJson()),
          before.records.map((record) => record.toJson()));
      expect(after.history, hasLength(before.history.length));
    });
  });

  group('warnings', () {
    test('a newly created inventory is reported once on stderr', () {
      final fresh = '${temporary.path}/typo.sqlite';
      final first =
          run(['check', '10.64.1.0/24', '--routing-domain', 'x'], db: fresh);
      expect(first.code, 0, reason: first.error);
      expect(first.error, contains('created a new empty inventory at $fresh'));
      expect(first.output, isNot(contains('created a new')));
      final second = run(['list'], db: fresh);
      expect(second.error, isNot(contains('created a new')));
    });

    test('an unknown routing domain names near matches without new exit codes',
        () {
      seed([
        _pool,
        _vcn,
        _subnet,
        const PrefixRecord(
            id: 'retired',
            cidr: '192.0.2.0/24',
            name: 'Retired',
            routingDomain: 'example-legacy',
            status: PrefixStatus.retired),
      ]);
      final typo = run(
          ['check', '10.64.1.0/24', '--routing-domain', 'example-corprate']);
      expect(typo.code, 0);
      expect(typo.output, contains('No conflicts'));
      expect(typo.error, contains('"example-corprate" has no existing'));
      expect(typo.error, contains('Did you mean: example-corporate?'));
      expect(typo.error, contains('Known routing domains: example-corporate.'));

      final cased = run(
          ['check', '10.64.1.0/24', '--routing-domain', 'EXAMPLE-CORPORATE']);
      expect(cased.code, 0);
      expect(cased.error, contains('Did you mean: example-corporate?'));

      final retiredOnly =
          run(['check', '192.0.2.0/24', '--routing-domain', 'example-legacy']);
      expect(retiredOnly.error, contains('"example-legacy" has no existing'));
      expect(retiredOnly.error, isNot(contains('Did you mean')));

      final known = run(
          ['check', '10.64.1.0/24', '--routing-domain', 'example-corporate']);
      expect(known.code, 3);
      expect(known.error, isNot(contains('Warning')));

      final reserved = run([
        'reserve',
        '10.64.1.0/24',
        '--name',
        'Typo reservation',
        '--routing-domain',
        'example-corprate',
      ]);
      expect(reserved.code, 0, reason: reserved.error);
      expect(reserved.error, contains('Did you mean: example-corporate?'));

      final recommendErrors = StringBuffer();
      final recommended = runCidrctl([
        '--db',
        database,
        'recommend',
        '--pool',
        '10.64.0.0/16',
        '--routing-domain',
        'Example-Corporate',
        '--prefix',
        '24',
      ], out: StringBuffer(), err: recommendErrors);
      expect(recommended, 0);
      // The earlier typo reservation created a second, near-matching domain.
      expect('$recommendErrors',
          contains('Did you mean: example-corporate, example-corprate?'));
    });

    test('an empty inventory says so instead of listing no domains', () {
      final result = run(['check', '10.0.0.0/24', '--routing-domain', 'lab']);
      expect(result.code, 0);
      expect(result.error, contains('no non-retired records in any'));
    });
  });

  group('usage errors', () {
    test('an unknown command names itself on stderr', () {
      final result = run(['frobnicate']);
      expect(result.code, 2);
      expect(result.error, contains('unknown command frobnicate'));
      expect(File(database).existsSync(), isFalse);
    });

    test('a blank --db is a usage error', () {
      final result = runCidrctl(['--db', ' ', 'list'],
          out: StringBuffer(), err: StringBuffer());
      expect(result, 2);
    });

    test('OCI JSON without a routing domain is a usage error for every type',
        () {
      final bundle = File('${temporary.path}/bundle.json')
        ..writeAsStringSync(jsonEncode({
          'metadata': {'tenancy': 'fictional-tenancy', 'region': 'us-1'},
          'vcns': [],
          'subnets': [],
        }));
      for (final type in [
        <String>[],
        ['json'],
        ['oci']
      ]) {
        final result = run(['import', ...type, '--file', bundle.path]);
        expect(result.code, 2, reason: '$type: ${result.error}');
        expect(result.error, contains('--routing-domain is required'));
      }
    });

    test('a routing domain is rejected for CSV and Atlas backups', () {
      final csv = File('${temporary.path}/inventory.csv')
        ..writeAsStringSync('id,cidr,name,routingDomain\n'
            'one,192.168.4.0/24,lab,isolated\n');
      final backup = File('${temporary.path}/backup.json')
        ..writeAsStringSync(InventoryImport.exportJson([_pool]));
      for (final args in [
        ['csv', '--file', csv.path],
        ['--file', csv.path],
        ['--file', backup.path],
        ['json', '--file', backup.path],
      ]) {
        final result =
            run(['import', ...args, '--routing-domain', 'other-domain']);
        expect(result.code, 2, reason: '$args: ${result.error}');
        expect(result.error, contains('applies only to OCI JSON'));
      }
      expect(run(['import', '--file', backup.path]).code, 0);
    });

    test('history --limit accepts only decimal integers', () {
      for (final limit in ['0x2', '+2', '0', '-1', '2.0']) {
        expect(run(['history', '--limit', limit]).code, 2, reason: limit);
      }
      expect(run(['history', '--limit', '2']).code, 0);
    });
  });

  group('default database location', () {
    test('commands without --db use the shared application path', () {
      final environment = {'HOME': '${temporary.path}/home'};
      final expected = defaultDatabasePath(environment);
      final result = run([
        'reserve',
        '10.42.0.0/24',
        '--name',
        'Fictional default',
        '--routing-domain',
        'lab',
      ], environment: environment);
      expect(result.code, 0, reason: result.error);
      expect(File(expected).existsSync(), isTrue);
      expect(result.error, contains(expected));
      if (Platform.isMacOS) {
        expect(
            expected,
            '${temporary.path}/home/Library/Application Support/'
            'cidr_atlas/inventory.sqlite');
      }
    });

    test('a missing home directory without --db is a usage error', () {
      final result = run(['list'], environment: const {});
      expect(result.code, 2);
      expect(result.error, contains('specify --db'));
    }, testOn: '!windows');
  });

  test('--version reports the package version from pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!;
    final result = run(['--version']);
    expect(result.code, 0);
    expect(result.output.trim(), 'cidrctl ${version.group(1)}');
  });
}
