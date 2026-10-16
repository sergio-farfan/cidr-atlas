// CIDR Atlas
// Command-line inventory integration tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'package:cidr_cli/cidr_cli.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String database;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('cidr_cli_test_');
    database = '${temporary.path}/inventory.sqlite';
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  ({int code, String output, String error}) run(List<String> args) {
    final output = StringBuffer();
    final error = StringBuffer();
    final code =
        runCidrctl(['--db', database, ...args], out: output, err: error);
    return (code: code, output: '$output', error: '$error');
  }

  test('reserve persists a prefix and list emits a portable JSON backup', () {
    final result = run([
      'reserve',
      '10.42.0.0/20',
      '--name',
      'production',
      '--routing-domain',
      'corporate',
      '--id',
      'production',
    ]);
    expect(result.code, 0, reason: result.error);
    final listing = run(['list', '--format', 'json']);
    expect(listing.code, 0);
    final json = jsonDecode(listing.output) as Map<String, dynamic>;
    expect((json['records'] as List).single['cidr'], '10.42.0.0/20');
  });

  test('conflicting reserve exits 3 without writing a second record', () {
    expect(
        run([
          'reserve',
          '10.42.0.0/20',
          '--name',
          'production',
          '--routing-domain',
          'corporate',
          '--id',
          'first',
        ]).code,
        0);
    final result = run([
      'reserve',
      '10.42.1.0/24',
      '--name',
      'overlap',
      '--routing-domain',
      'corporate',
      '--id',
      'second',
    ]);
    expect(result.code, 3);
    final store = InventoryStore.open(database);
    try {
      expect(store.list(), hasLength(1));
    } finally {
      store.close();
    }
  });

  test('intentional containment needs an explicit parent', () {
    expect(
        run([
          'reserve',
          '10.42.0.0/16',
          '--name',
          'pool',
          '--kind',
          'allocation',
          '--routing-domain',
          'corporate',
          '--id',
          'pool',
        ]).code,
        0);
    final withoutParent = run([
      'check',
      '10.42.0.0/20',
      '--routing-domain',
      'corporate',
    ]);
    expect(withoutParent.code, 3);
    final withParent = run([
      'check',
      '10.42.0.0/20',
      '--routing-domain',
      'corporate',
      '--parent',
      'pool',
    ]);
    expect(withParent.code, 0, reason: withParent.error);
  });

  test('CSV import is a preview until --apply is explicit', () {
    final file = File('${temporary.path}/inventory.csv')
      ..writeAsStringSync('id,cidr,name,routingDomain\n'
          'one,192.168.4.0/24,lab,isolated\n');
    final preview = run(['import', 'csv', '--file', file.path]);
    expect(preview.code, 0, reason: preview.error);
    expect(preview.output, contains('Preview only'));
    var store = InventoryStore.open(database);
    expect(store.list(), isEmpty);
    store.close();
    final apply = run(['import', 'csv', '--file', file.path, '--apply']);
    expect(apply.code, 0, reason: apply.error);
    store = InventoryStore.open(database);
    expect(store.list(), hasLength(1));
    store.close();
  });

  test('check allows reuse in a separate routing domain', () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
      id: 'existing',
      cidr: '10.42.0.0/16',
      name: 'existing',
      routingDomain: 'customer-a',
    ));
    store.close();
    expect(
        run([
          'check',
          '10.42.0.0/16',
          '--routing-domain',
          'customer-b',
        ]).code,
        0);
  });

  test('bad flags and missing routing domain use usage exit code', () {
    expect(run(['check', '10.42.0.0/16']).code, 2);
    expect(run(['reserve', '--unknown']).code, 2);
    expect(run(['check', '10.42.1.1/24', '--routing-domain', 'corporate']).code,
        2);
  });

  test('export writes a restorable JSON file', () {
    expect(
        run([
          'reserve',
          '2001:db8::/48',
          '--name',
          'IPv6 documentation',
          '--routing-domain',
          'lab',
        ]).code,
        0);
    final destination = '${temporary.path}/backup.json';
    expect(run(['export', '--file', destination]).code, 0);
    final preview = InventoryImport.json(File(destination).readAsStringSync(),
        routingDomain: '');
    expect(preview.canApply, isTrue, reason: preview.errors.join('; '));
    expect(preview.records.single.cidr, '2001:db8::/48');
  });

  test(
      'OCI preview reconciles manual resource identity before checking conflicts',
      () {
    const resourceId = 'ocid1.vcn.oc1.phx.FICTIONAL';
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
      id: 'manual-vcn',
      cidr: '10.80.0.0/20',
      name: 'planned label',
      routingDomain: 'corporate',
      resourceId: resourceId,
      tenancy: 'example-tenancy',
      region: 'us-phoenix-1',
      owner: 'Architect',
      notes: 'Keep local planning notes',
    ));
    store.close();
    final file = File('${temporary.path}/oci.json')
      ..writeAsStringSync(jsonEncode({
        'metadata': {
          'tenancy': 'example-tenancy',
          'region': 'us-phoenix-1',
        },
        'vcns': [
          {
            'id': resourceId,
            'display-name': 'discovered label',
            'cidr-blocks': ['10.80.0.0/20'],
          },
        ],
        'subnets': [],
      }));
    final preview = run([
      'import',
      'oci',
      '--file',
      file.path,
      '--routing-domain',
      'corporate',
    ]);
    expect(preview.code, 0, reason: preview.error);
    expect(preview.output, isNot(contains('conflict(s)')));
    final applied = run([
      'import',
      'oci',
      '--file',
      file.path,
      '--routing-domain',
      'corporate',
      '--apply',
    ]);
    expect(applied.code, 0, reason: applied.error);
    final reopened = InventoryStore.open(database);
    try {
      expect(reopened.list(), hasLength(1));
      final record = reopened.list().single;
      expect(record.id, 'manual-vcn');
      expect(record.owner, 'Architect');
      expect(record.notes, 'Keep local planning notes');
      expect(record.status, PrefixStatus.reserved);
    } finally {
      reopened.close();
    }
  });

  test('filtered export includes ancestors and imports into a fresh inventory',
      () {
    final store = InventoryStore.open(database);
    store.saveAll(const [
      PrefixRecord(
        id: 'pool',
        cidr: '10.70.0.0/16',
        name: 'pool',
        routingDomain: 'corporate',
        kind: PrefixKind.allocation,
      ),
      PrefixRecord(
        id: 'vcn',
        cidr: '10.70.0.0/20',
        name: 'production',
        routingDomain: 'corporate',
        parentId: 'pool',
        status: PrefixStatus.active,
      ),
    ]);
    store.close();
    final destination = '${temporary.path}/filtered.json';
    final result = run([
      'export',
      '--status',
      'active',
      '--file',
      destination,
    ]);
    expect(result.code, 0, reason: result.error);
    final preview = InventoryImport.json(File(destination).readAsStringSync(),
        routingDomain: '');
    expect(preview.canApply, isTrue, reason: preview.errors.join('; '));
    final fresh = InventoryStore.open('${temporary.path}/fresh.sqlite');
    try {
      fresh.applyImport(preview);
      expect(fresh.list().map((record) => record.id),
          containsAll(['pool', 'vcn']));
      expect(fresh.list(), hasLength(2));
    } finally {
      fresh.close();
    }
  });

  test('partial CSV import can refer to an existing parent', () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
      id: 'pool',
      cidr: '10.70.0.0/16',
      name: 'pool',
      routingDomain: 'corporate',
      kind: PrefixKind.allocation,
    ));
    store.close();
    final file = File('${temporary.path}/partial.csv')
      ..writeAsStringSync('id,cidr,name,routingDomain,parentId\n'
          'vcn,10.70.0.0/20,production,corporate,pool\n');
    final result = run(['import', 'csv', '--file', file.path, '--apply']);
    expect(result.code, 0, reason: result.error);
    final reopened = InventoryStore.open(database);
    try {
      expect(reopened.list(), hasLength(2));
      expect(
          reopened.list().firstWhere((record) => record.id == 'vcn').parentId,
          'pool');
    } finally {
      reopened.close();
    }
  });
}
