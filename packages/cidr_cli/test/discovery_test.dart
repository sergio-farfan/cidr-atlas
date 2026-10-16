// CIDR Atlas CLI discovery selection, preview, and atomic persistence tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'package:cidr_cli/cidr_cli.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_oci/cidr_oci.dart';
import 'package:test/test.dart';

const _scope = [
  'discover',
  'oci',
  '--profile',
  'FICTIONAL',
  '--region',
  'us-phoenix-1',
  '--compartment-id',
  'fictional-compartment',
  '--routing-domain',
  'corporate',
];

String _bundle({String cidr = '10.80.0.0/20'}) => jsonEncode({
      'metadata': {
        'tenancy': 'fictional-tenancy',
        'region': 'us-phoenix-1',
        'collectedAt': '2026-10-15T12:00:00Z'
      },
      'vcns': [
        {
          'id': 'fictional-vcn',
          'display-name': 'observed label',
          'compartment-id': 'fictional-compartment',
          'cidr-blocks': [cidr]
        }
      ],
      'subnets': [],
    });

class FakeOciInventoryClient implements OciInventoryClient {
  String bundle = _bundle();
  OciException? failure;
  Object? unexpectedFailure;
  void Function(OciCancellation)? duringDiscovery;
  String? selectedProfile, selectedConfig, selectedExecutable;
  OciAuthMode? selectedAuth;
  String? selectedRegion, selectedCompartment;
  List<String> selectedRegions = [];
  bool allRegions = false;
  bool allCompartments = false;
  int calls = 0;
  List<OciDiscoveryProgress> progress = [
    const OciDiscoveryProgress(
        message: 'Reading fictional subnets',
        collectionTimeout: OciCollectionLimits.singleScope),
  ];

  @override
  Future<OciConnection> connection(
      {required String profile,
      String? configFile,
      String? executable,
      OciAuthMode? authMode}) async {
    calls++;
    selectedProfile = profile;
    selectedConfig = configFile;
    selectedExecutable = executable;
    selectedAuth = authMode;
    return OciConnection(
        executable: executable ?? '/fictional/oci',
        configFile: configFile ?? '/fictional/config',
        profile: profile,
        tenancyId: 'fictional-tenancy',
        authMode: authMode ?? OciAuthMode.apiKey);
  }

  @override
  Future<OciDiscovery> discover(OciConnection connection,
      {List<String> regions = const [],
      bool allRegions = false,
      String? compartmentId,
      bool allCompartments = false,
      OciCancellation? cancellation,
      void Function(String)? onProgress,
      void Function(OciDiscoveryProgress)? onDiscoveryProgress}) async {
    calls++;
    selectedRegions = regions;
    selectedRegion = regions.firstOrNull;
    this.allRegions = allRegions;
    this.allCompartments = allCompartments;
    selectedCompartment = compartmentId;
    for (final event in progress) {
      onProgress?.call(event.message);
      onDiscoveryProgress?.call(event);
    }
    duringDiscovery?.call(cancellation!);
    if (failure != null) throw failure!;
    if (unexpectedFailure != null) throw unexpectedFailure!;
    return OciDiscovery(
        bundleJson: bundle, warnings: ['Fictional coverage warning']);
  }

  @override
  Future<List<OciProfile>> profiles({String? configFile}) =>
      throw StateError('Discovery must use the explicit profile.');
  @override
  Future<List<OciRegion>> regions(OciConnection connection,
          {OciCancellation? cancellation}) =>
      throw StateError('Discovery must use the explicit region.');
  @override
  Future<List<OciCompartment>> compartments(OciConnection connection,
          {required String region, OciCancellation? cancellation}) =>
      throw StateError('Discovery must use the explicit compartment.');
}

void main() {
  late Directory temporary;
  late String database;
  late FakeOciInventoryClient client;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('cidr_discovery_test_');
    database = '${temporary.path}/inventory.sqlite';
    client = FakeOciInventoryClient();
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<({int code, String output, String error})> run(List<String> args,
      {OciCancellation? cancellation}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCidrctlAsync(['--db', database, ...args],
        out: out, err: err, ociClient: client, cancellation: cancellation);
    return (code: code, output: '$out', error: '$err');
  }

  ({List<PrefixRecord> records, int history}) snapshot() {
    final store = InventoryStore.open(database);
    try {
      return (records: store.list(), history: store.history().length);
    } finally {
      store.close();
    }
  }

  void seed(List<PrefixRecord> records) {
    final store = InventoryStore.open(database);
    try {
      store.saveAll(records);
    } finally {
      store.close();
    }
  }

  test('discovery help documents scope and overrides without contacting OCI',
      () async {
    for (final args in [
      ['discover', '--help'],
      ['discover', 'oci', '--help']
    ]) {
      final result = await run(args);
      expect(result.code, 0);
      expect(result.output, contains('cidrctl discover oci'));
      for (final flag in [
        '--profile',
        '--region',
        '--all-regions',
        '--compartment-id',
        '--all-compartments',
        '--routing-domain',
        '--config-file',
        '--oci-bin',
        '--auth',
        '--collection-timeout',
        '--apply'
      ]) {
        expect(result.output, contains(flag));
      }
    }
    expect(client.calls, 0);
    expect(File(database).existsSync(), isFalse);
  });

  for (final flag in [
    '--profile',
    '--region',
    '--compartment-id',
    '--routing-domain'
  ]) {
    test('missing $flag is usage error before discovery', () async {
      final args = [..._scope];
      final index = args.indexOf(flag);
      args.removeRange(index, index + 2);
      final result = await run(args);
      expect(result.code, 2);
      expect(result.error, contains('$flag is required'));
      expect(client.calls, 0);
      expect(File(database).existsSync(), isFalse);
    });
  }

  test(
      'invalid provider, auth, extra positional and blank scope are usage errors',
      () async {
    for (final args in [
      ['discover', 'aws'],
      [..._scope, '--auth', 'instance_principal'],
      [..._scope, 'unexpected'],
      [..._scope, '--region', '  '],
    ]) {
      expect((await run(args)).code, 2);
    }
    expect(client.calls, 0);
  });

  test('multiple selected regions accept repeated and comma separated values',
      () async {
    final result =
        await run([..._scope, '--region', 'eu-frankfurt-1, us-phoenix-1']);
    expect(result.code, 0, reason: result.error);
    expect(client.selectedRegions, ['us-phoenix-1', 'eu-frankfurt-1']);
    expect(client.allRegions, isFalse);
    expect(client.allCompartments, isFalse);
    expect(snapshot().history, 0);
  });

  test('all subscribed regions and accessible compartments preview in one run',
      () async {
    final result = await run([
      'discover',
      'oci',
      '--profile',
      'FICTIONAL',
      '--all-regions',
      '--all-compartments',
      '--routing-domain',
      'corporate',
    ]);
    expect(result.code, 0, reason: result.error);
    expect(client.allRegions, isTrue);
    expect(client.selectedRegions, isEmpty);
    expect(client.allCompartments, isTrue);
    expect(client.selectedCompartment, isNull);
    expect(snapshot().records, isEmpty);
    expect(snapshot().history, 0);
  });

  test('mixed broad and selected dimensions stay independent', () async {
    for (final allRegions in [true, false]) {
      final result = await run([
        'discover',
        'oci',
        '--profile',
        'FICTIONAL',
        if (allRegions) '--all-regions' else ...['--region', 'us-phoenix-1'],
        if (!allRegions)
          '--all-compartments'
        else ...['--compartment-id', 'fictional-compartment'],
        '--routing-domain',
        'corporate',
      ]);
      expect(result.code, 0, reason: result.error);
      expect(client.allRegions, allRegions);
      expect(client.allCompartments, !allRegions);
    }
  });

  test(
      'conflicting modes and blank region members fail before connection or db',
      () async {
    for (final args in [
      [..._scope, '--all-regions'],
      [..._scope, '--all-compartments'],
      [..._scope, '--region', 'eu-frankfurt-1,'],
      [..._scope, '--region', ',eu-frankfurt-1'],
      [..._scope, '--region', 'eu-frankfurt-1, ,us-phoenix-1'],
    ]) {
      final result = await run(args);
      expect(result.code, 2, reason: '$args: ${result.error}');
      expect(client.calls, 0);
      expect(File(database).existsSync(), isFalse);
    }
  });

  test('explicit overrides reach the shared client and preview writes nothing',
      () async {
    final result = await run([
      ..._scope,
      '--config-file',
      '/fictional/custom config',
      '--oci-bin',
      '/fictional/bin/oci',
      '--auth',
      'security_token'
    ]);
    expect(result.code, 0, reason: result.error);
    expect(result.output, contains('OCI JSON'));
    expect(result.output, contains('Preview only'));
    expect(result.output, contains('Fictional coverage warning'));
    expect(result.error, contains('Reading fictional subnets'));
    expect(result.output, isNot(contains('Reading fictional subnets')));
    expect(client.selectedProfile, 'FICTIONAL');
    expect(client.selectedConfig, '/fictional/custom config');
    expect(client.selectedExecutable, '/fictional/bin/oci');
    expect(client.selectedAuth, OciAuthMode.securityToken);
    expect(client.selectedRegion, 'us-phoenix-1');
    expect(client.selectedCompartment, 'fictional-compartment');
    expect(snapshot().records, isEmpty);
    expect(snapshot().history, 0);
  });

  test('apply persists OCI records and import history atomically', () async {
    final result = await run([..._scope, '--apply', '--auth', 'api_key']);
    expect(result.code, 0, reason: result.error);
    final state = snapshot();
    expect(state.records.single.cidr, '10.80.0.0/20');
    expect(state.records.single.source, 'oci');
    expect(state.records.single.routingDomain, 'corporate');
    expect(state.records.single.verifiedAt, DateTime.utc(2026, 10, 15, 12));
    expect(state.history, 1);
    expect(client.selectedAuth, OciAuthMode.apiKey);
    expect(temporary.listSync().whereType<File>().map((f) => f.path),
        everyElement(isNot(endsWith('.json'))));
  });

  test('required list failure cannot persist partial inventory or history',
      () async {
    seed([
      const PrefixRecord(
          id: 'existing',
          cidr: '192.0.2.0/24',
          name: 'existing',
          routingDomain: 'corporate')
    ]);
    final before = snapshot();
    client.failure =
        const OciException('Subnet list failed. Check read permissions.');
    for (final scope in [
      _scope,
      [
        'discover',
        'oci',
        '--profile',
        'FICTIONAL',
        '--all-regions',
        '--all-compartments',
        '--routing-domain',
        'corporate'
      ],
    ]) {
      final result = await run([...scope, '--apply']);
      expect(result.code, 1);
      expect(result.error, contains('Subnet list failed'));
      expect(snapshot().records.map((r) => r.id), ['existing']);
      expect(snapshot().history, before.history);
    }
  });

  test('cancelled discovery ignores late successful completion without writes',
      () async {
    final cancellation = OciCancellation();
    client.duringDiscovery = (token) => token.cancel();
    final result =
        await run([..._scope, '--apply'], cancellation: cancellation);
    expect(result.code, 1);
    expect(result.error.toLowerCase(), contains('cancel'));
    expect(snapshot().records, isEmpty);
    expect(snapshot().history, 0);
  });

  test('pre-cancelled discovery does not contact OCI', () async {
    final cancellation = OciCancellation()..cancel();
    expect((await run([..._scope, '--apply'], cancellation: cancellation)).code,
        1);
    expect(client.calls, 0);
  });

  test('unexpected adapter failure hides raw output and creates no database',
      () async {
    client.unexpectedFailure = StateError('fictional-secret-do-not-display');
    final result = await run([..._scope, '--apply']);
    expect(result.code, 1);
    expect(result.error, contains('Discovery failed'));
    expect(result.error, isNot(contains('fictional-secret-do-not-display')));
    expect(File(database).existsSync(), isFalse);
  });

  test(
      'default auth preserves profile choice and command db overrides global db',
      () async {
    final override = '${temporary.path}/override.sqlite';
    final result = await run([..._scope, '--apply', '--db', override]);
    expect(result.code, 0, reason: result.error);
    expect(client.selectedAuth, isNull);
    expect(File(database).existsSync(), isFalse);
    final store = InventoryStore.open(override);
    try {
      expect(store.list().single.routingDomain, 'corporate');
    } finally {
      store.close();
    }
  });

  test('malformed bundle is an operation error and invalid CIDRs cannot apply',
      () async {
    seed([
      const PrefixRecord(
          id: 'existing',
          cidr: '192.0.2.0/24',
          name: 'existing',
          routingDomain: 'corporate')
    ]);
    final before = snapshot();
    for (final bundle in ['{broken', _bundle(cidr: '10.80.1.1/20')]) {
      client.bundle = bundle;
      final result = await run([..._scope, '--apply']);
      expect(result.code, 1, reason: result.error);
      expect(snapshot().records.map((r) => r.id), ['existing']);
      expect(snapshot().history, before.history);
    }
  });

  test('refresh preserves planning metadata and retains absent resources',
      () async {
    seed([
      const PrefixRecord(
          id: 'manual-vcn',
          cidr: '10.80.0.0/20',
          name: 'planned label',
          routingDomain: 'corporate',
          resourceId: 'fictional-vcn',
          tenancy: 'fictional-tenancy',
          region: 'us-phoenix-1',
          owner: 'Architect',
          notes: 'Keep local notes',
          environment: 'planning',
          customer: 'Fictional customer'),
      const PrefixRecord(
          id: 'absent',
          cidr: '192.0.2.0/24',
          name: 'absent',
          routingDomain: 'corporate')
    ]);
    final result = await run([..._scope, '--apply']);
    expect(result.code, 0, reason: result.error);
    expect(result.output, isNot(contains('conflict(s)')));
    final records = snapshot().records;
    expect(records, hasLength(2));
    final refreshed = records.firstWhere((r) => r.id == 'manual-vcn');
    expect(refreshed.owner, 'Architect');
    expect(refreshed.notes, 'Keep local notes');
    expect(refreshed.status, PrefixStatus.reserved);
    expect(refreshed.environment, 'planning');
    expect(refreshed.customer, 'Fictional customer');
    expect(records.map((r) => r.id), contains('absent'));
  });

  test('routing domains isolate identity and conflict checking', () async {
    seed([
      const PrefixRecord(
          id: 'other-domain',
          cidr: '10.80.0.0/20',
          name: 'independent',
          routingDomain: 'separate',
          resourceId: 'fictional-vcn',
          tenancy: 'fictional-tenancy',
          region: 'us-phoenix-1')
    ]);
    final result = await run([..._scope, '--apply']);
    expect(result.code, 0, reason: result.error);
    expect(result.output, isNot(contains('conflict(s)')));
    expect(snapshot().records, hasLength(2));
    expect(snapshot().records.map((r) => r.routingDomain),
        containsAll(['corporate', 'separate']));
  });

  test('real discovered overlap is previewed and retained for review on apply',
      () async {
    seed([
      const PrefixRecord(
          id: 'overlap',
          cidr: '10.80.0.0/24',
          name: 'unrelated',
          routingDomain: 'corporate')
    ]);
    final preview = await run(_scope);
    expect(preview.code, 0, reason: preview.error);
    expect(preview.output, contains('1 conflict(s)'));
    expect(snapshot().records, hasLength(1));
    final applied = await run([..._scope, '--apply']);
    expect(applied.code, 0, reason: applied.error);
    expect(InventoryRules.conflicts(snapshot().records), hasLength(1));
  });

  test('existing synchronous commands retain their async wrapper behavior',
      () async {
    final result = await run(['list']);
    expect(result.code, 0);
    expect(result.output, contains('No prefixes found'));
    expect(client.calls, 0);
  });

  test('existing usage errors retain synchronous diagnostics through wrapper',
      () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = runCidrctl(['--db', database, 'reserve', '--unknown'],
        out: out, err: err);
    final result = await run(['reserve', '--unknown']);
    expect(result.code, code);
    expect(result.output, '$out');
    expect(result.error, '$err');
  });

  group('empty discovery', () {
    String empty() => jsonEncode({
          'metadata': {
            'tenancy': 'fictional-tenancy',
            'region': 'us-phoenix-1',
            'collectedAt': '2026-10-15T12:00:00Z'
          },
          'vcns': [],
          'subnets': [],
        });

    test('is a neutral success that writes nothing, with and without apply',
        () async {
      client.bundle = empty();
      for (final apply in [false, true]) {
        final result = await run([..._scope, if (apply) '--apply']);
        expect(result.code, 0, reason: result.error);
        expect(result.output, contains('no networks were found'));
        expect(result.output, contains('Fictional coverage warning'));
        expect(result.error, isNot(contains('Error:')));
        expect(result.error, isNot(contains('cannot be applied')));
        expect(File(database).existsSync(), isFalse);
      }
    });

    test('leaves an existing inventory and its history unchanged', () async {
      seed([
        const PrefixRecord(
            id: 'existing',
            cidr: '192.0.2.0/24',
            name: 'existing',
            routingDomain: 'corporate')
      ]);
      final before = snapshot();
      client.bundle = empty();
      final result = await run([..._scope, '--apply']);
      expect(result.code, 0, reason: result.error);
      expect(snapshot().records.map((r) => r.id), ['existing']);
      expect(snapshot().history, before.history);
    });
  });

  test('database location is resolved before contacting OCI', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runCidrctlAsync(_scope,
        out: out, err: err, environment: const {}, ociClient: client);
    expect(code, 2, reason: '$err');
    expect('$err', contains('specify --db'));
    expect(client.calls, 0);

    Directory('${temporary.path}/folder.sqlite').createSync();
    final directory =
        await run([..._scope, '--db', '${temporary.path}/folder.sqlite']);
    expect(directory.code, 1);
    expect(directory.error, contains('folder.sqlite'));
    expect(client.calls, 0);

    File('${temporary.path}/plain-file').writeAsStringSync('not a folder');
    final insideFile = await run(
        [..._scope, '--db', '${temporary.path}/plain-file/inventory.sqlite']);
    expect(insideFile.code, 1);
    expect(client.calls, 0);

    final blank = await run([..._scope, '--db', ' ']);
    expect(blank.code, 2);
    expect(client.calls, 0);
  });

  test('--apply with a read-only database fails before contacting OCI',
      () async {
    final uid = Process.runSync('id', ['-u']);
    if ('${uid.stdout}'.trim() == '0') {
      markTestSkipped('root can write a read-only file');
      return;
    }
    seed([
      const PrefixRecord(
          id: 'existing',
          cidr: '192.0.2.0/24',
          name: 'existing',
          routingDomain: 'corporate')
    ]);
    // Process.runSync passes arguments directly; no shell is involved.
    final chmod = Process.runSync('chmod', ['400', database]);
    expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    addTearDown(() => Process.runSync('chmod', ['600', database]));

    final apply = await run([..._scope, '--apply']);
    expect(apply.code, 1, reason: apply.error);
    expect(apply.error, contains('inventory.sqlite'));
    expect(client.calls, 0);

    // A preview does not write, so it is not refused before collection.
    await run(_scope);
    expect(client.calls, greaterThan(0));
  }, testOn: '!windows');

  test('collection timeout is validated before contacting OCI', () async {
    for (final value in ['0', '29', '86401', '-1', 'abc', '1e3', '60.5', ' ']) {
      final result = await run([..._scope, '--collection-timeout', value]);
      expect(result.code, 2, reason: value);
      expect(result.error, contains('--collection-timeout'));
    }
    expect(client.calls, 0);
    final accepted = await run([..._scope, '--collection-timeout', '3600']);
    expect(accepted.code, 0, reason: accepted.error);
  });

  test('progress names configuration, profile and scope count on stderr',
      () async {
    client.progress = [
      for (final (message, scopes, completed) in [
        ('Loading accessible active compartments and descendants', null, 0),
        (
          'Loading VCN list in region us-phoenix-1, compartment c1 '
              '(scope 1/6; 0 completed)',
          6,
          0
        ),
        (
          'Loading subnet list in region us-phoenix-1, compartment c1 '
              '(scope 1/6; 0 completed)',
          6,
          0
        ),
        (
          'Loading VCN list in region us-phoenix-1, compartment c2 '
              '(scope 2/6; 1 completed)',
          6,
          1
        ),
      ])
        OciDiscoveryProgress(
            message: message,
            scopeCount: scopes,
            completedScopes: completed,
            collectionTimeout: OciCollectionLimits.broadScope),
    ];
    final result = await run([
      'discover',
      'oci',
      '--profile',
      'FICTIONAL',
      '--all-regions',
      '--all-compartments',
      '--routing-domain',
      'corporate',
      '--collection-timeout',
      '7200',
    ]);
    expect(result.code, 0, reason: result.error);
    expect(
        result.error,
        contains('Using OCI configuration /fictional/config, '
            'profile FICTIONAL (api_key authentication).'));
    expect(
        'Collecting 6 region/compartment scopes with 12 sequential list '
                'requests within the 7200-second collection limit.'
            .allMatches(result.error),
        hasLength(1));
    final lines = result.error.split('\n');
    expect(lines.indexWhere((line) => line.startsWith('Collecting 6')),
        lessThan(lines.indexWhere((line) => line.contains('scope 1/6'))));
    expect(result.output, isNot(contains('/fictional/config')));
    expect(result.output, isNot(contains('Collecting')));
  });

  test('scope count line states the default limit the adapter reports',
      () async {
    client.progress = [
      const OciDiscoveryProgress(
          message: 'Resolving region keys from region subscriptions',
          collectionTimeout: OciCollectionLimits.broadScope),
      OciDiscoveryProgress(
          message: 'Loading VCN list in region us-phoenix-1, compartment '
              'fictional-compartment (scope 1/1; 0 completed)',
          scopeCount: 1,
          collectionTimeout: OciCollectionLimits.singleScope),
    ];
    final result = await run(_scope);
    expect(result.code, 0, reason: result.error);
    expect(
        'Collecting 1 region/compartment scope with 2 sequential list '
                'requests within the 180-second default collection limit.'
            .allMatches(result.error),
        hasLength(1));
    // Both adapter lines are still relayed.
    expect(result.error, contains('Resolving region keys'));
    expect(result.error, contains('(scope 1/1; 0 completed)'));
  });

  test('new inventory and unknown routing domain warn without changing exit',
      () async {
    final created = await run([..._scope, '--apply']);
    expect(created.code, 0, reason: created.error);
    expect(created.error, contains('created a new empty inventory'));
    final again = await run([
      ...[..._scope]..[_scope.indexOf('corporate')] = 'Corporate',
    ]);
    expect(again.code, 0, reason: again.error);
    expect(again.error, isNot(contains('created a new empty inventory')));
    expect(again.error, contains('Did you mean: corporate?'));
  });
}
