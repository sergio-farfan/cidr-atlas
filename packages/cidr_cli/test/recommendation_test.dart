// CIDR Atlas
// Recommendation preview, sizing, and atomic reservation integration tests.
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
    temporary = Directory.systemTemp.createTempSync('atlas_recommendation_');
    database = '${temporary.path}/inventory.sqlite';
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  ({int code, String out, String err}) run(List<String> arguments) {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = runCidrctl(['--db', database, 'recommend', ...arguments],
        out: out, err: err);
    return (code: code, out: '$out', err: '$err');
  }

  const scope = ['--pool', '10.90.0.0/20', '--routing-domain', 'fictional'];

  test('prefix preview reports exact slots and writes no inventory or history',
      () {
    final result =
        run([...scope, '--prefix', '24', '--limit', '3', '--format', 'json']);
    expect(result.code, 0, reason: result.err);
    final plan = jsonDecode(result.out) as Map<String, dynamic>;
    expect(plan['summary']['freeSlots'], '16');
    expect(plan['candidates'], hasLength(3));
    final store = InventoryStore.open(database);
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
    store.close();
  });

  test('demand sizes 100 plus growth and maintenance as an OCI /25', () {
    final result = run([
      ...scope,
      '--addresses',
      '100',
      '--growth-percent',
      '20',
      '--additional',
      '4',
      '--format',
      'json'
    ]);
    expect(result.code, 0, reason: result.err);
    final plan = jsonDecode(result.out) as Map<String, dynamic>;
    expect(plan['prefixLength'], 25);
    expect(plan['targetAddresses'], '124');
    expect(plan['candidates'].first['details']['assignableAddresses'], '125');
  });

  test(
      'apply inherits the VCN scope and preserves the recommendation rationale',
      () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
        id: 'pool',
        cidr: '10.90.0.0/20',
        name: 'Fictional VCN',
        routingDomain: 'fictional',
        kind: PrefixKind.vcn,
        status: PrefixStatus.active,
        tenancy: 'fictional-tenancy',
        region: 'us-phoenix-1',
        resourceId: 'fictional-vcn',
        compartment: 'fictional-compartment',
        environment: 'Test'));
    store.close();
    final result = run([
      ...scope,
      '--parent',
      'pool',
      '--addresses',
      '100',
      '--growth-percent',
      '20',
      '--additional',
      '4',
      '--apply',
      '--name',
      'API subnet',
      '--notes',
      'Service owner reviewed.'
    ]);
    expect(result.code, 0, reason: result.err);
    final reopened = InventoryStore.open(database);
    final reserved =
        reopened.list().singleWhere((record) => record.id != 'pool');
    expect(reserved.kind, PrefixKind.subnet);
    expect(reserved.parentId, 'pool');
    expect(reserved.vcnId, 'fictional-vcn');
    expect(reserved.compartment, 'fictional-compartment');
    expect(reserved.environment, 'Test');
    expect(Cidr.parse(reserved.cidr).prefixLength, 25);
    expect(reserved.notes, contains('Service owner reviewed.'));
    expect(reserved.notes, contains('124'));
    expect(reserved.notes.toLowerCase(), contains('growth'));
    expect(InventoryRules.conflicts(reopened.list()), isEmpty);
    reopened.close();
  });

  test('demand needs an explicit growth choice and cannot use generic policy',
      () {
    expect(run([...scope, '--addresses', '100']).code, 2);
    expect(
        run([
          ...scope,
          '--addresses',
          '100',
          '--growth-percent',
          '0',
          '--policy',
          'generic'
        ]).code,
        2);
    expect(
        run([
          ...scope,
          '--prefix',
          '24',
          '--addresses',
          '100',
          '--growth-percent',
          '0'
        ]).code,
        2);
  });

  test('no-fit and missing apply name do not save a reservation', () {
    final noFit = run([
      '--pool',
      '10.90.0.0/30',
      '--routing-domain',
      'fictional',
      '--addresses',
      '2',
      '--growth-percent',
      '0',
      '--apply',
      '--name',
      'No fit'
    ]);
    expect(noFit.code, 1);
    expect(run([...scope, '--prefix', '24', '--apply']).code, 2);
    final store = InventoryStore.open(database);
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
    store.close();
  });

  test('generic IPv6 preview keeps exact totals and OCI rejects /31', () {
    final ipv6 = run([
      '--pool',
      '2001:db8::/64',
      '--routing-domain',
      'fictional',
      '--prefix',
      '128',
      '--limit',
      '2',
      '--format',
      'json'
    ]);
    expect(ipv6.code, 0, reason: ipv6.err);
    final plan = jsonDecode(ipv6.out) as Map<String, dynamic>;
    expect(plan['summary']['freeSlots'], '18446744073709551616');
    expect(plan['candidates'], hasLength(2));
    expect(run([...scope, '--prefix', '31', '--policy', 'oci_ipv4']).code, 1);
  });

  test('a partial blocker excludes its whole aligned slot', () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
        id: 'partial',
        cidr: '10.90.0.64/26',
        name: 'Partial slot',
        routingDomain: 'fictional'));
    store.close();
    final result = run([
      '--pool',
      '10.90.0.0/23',
      '--routing-domain',
      'fictional',
      '--prefix',
      '24',
      '--format',
      'json'
    ]);
    expect(result.code, 0, reason: result.err);
    final plan = jsonDecode(result.out) as Map<String, dynamic>;
    expect(plan['summary']['freeAddresses'], '448');
    expect(plan['summary']['freeSlots'], '1');
    expect((plan['candidates'] as List).single['cidr'], '10.90.1.0/24');
  });

  test('another routing domain does not block a recommendation', () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
        id: 'other',
        cidr: '10.90.0.0/20',
        name: 'Isolated pool',
        routingDomain: 'other-domain'));
    store.close();
    final result = run([...scope, '--prefix', '24', '--format', 'json']);
    expect(result.code, 0, reason: result.err);
    final plan = jsonDecode(result.out) as Map<String, dynamic>;
    expect(plan['summary']['freeSlots'], '16');
  });

  test('an allocation parent defaults to VCN and inherits planning scope', () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
        id: 'pool',
        cidr: '10.90.0.0/20',
        name: 'Fictional allocation',
        routingDomain: 'fictional',
        kind: PrefixKind.allocation,
        customer: 'Example customer',
        tenancy: 'fictional-tenancy',
        region: 'us-phoenix-1',
        compartment: 'fictional-compartment',
        environment: 'Test',
        owner: 'Architect'));
    store.close();
    final result = run([
      ...scope,
      '--parent',
      'pool',
      '--prefix',
      '24',
      '--apply',
      '--name',
      'Planned VCN',
      '--format',
      'json'
    ]);
    expect(result.code, 0, reason: result.err);
    final json = jsonDecode(result.out) as Map<String, dynamic>;
    final reservation = json['reservation'] as Map<String, dynamic>;
    expect(reservation['cidr'], json['candidates'].first['cidr']);
    expect(reservation['kind'], 'vcn');
    expect(reservation['parentId'], 'pool');
    expect(reservation['customer'], 'Example customer');
    expect(reservation['tenancy'], 'fictional-tenancy');
    expect(reservation['region'], 'us-phoenix-1');
    expect(reservation['compartment'], 'fictional-compartment');
    expect(reservation['environment'], 'Test');
    expect(reservation['owner'], 'Architect');
    expect(reservation['resourceId'], isEmpty);
    expect(reservation['vcnId'], isEmpty);
    final reopened = InventoryStore.open(database);
    expect(reopened.list(), hasLength(2));
    expect(reopened.history().first.action, 'reserve');
    reopened.close();
  });

  test('peak demand applies only the explicit growth allowance', () {
    final result = run([
      ...scope,
      '--addresses',
      '101',
      '--basis',
      'peak',
      '--growth-percent',
      '0',
      '--format',
      'json'
    ]);
    expect(result.code, 0, reason: result.err);
    final plan = jsonDecode(result.out) as Map<String, dynamic>;
    expect(plan['targetAddresses'], '101');
    expect(plan['prefixLength'], 25);
    expect(plan['candidates'].first['rationale'], contains('101 peak'));
    expect(plan['candidates'].first['rationale'], contains('0%'));
  });

  test('malformed numbers and irrelevant demand inputs are usage errors', () {
    for (final options in [
      ['--prefix', '-1'],
      ['--prefix', '33'],
      ['--prefix', '19'],
      ['--prefix', '24.5'],
      ['--prefix', '0x18'],
      ['--addresses', '0', '--growth-percent', '0'],
      ['--addresses', '-1', '--growth-percent', '0'],
      ['--addresses', '1.5', '--growth-percent', '0'],
      ['--addresses', '1', '--growth-percent', '-1'],
      ['--addresses', '1', '--growth-percent', '2.5'],
      ['--addresses', '1', '--growth-percent', '0', '--additional', '-1'],
      ['--addresses', '1', '--growth-percent', '0', '--additional', '1.5'],
      ['--prefix', '24', '--limit', '0'],
      ['--prefix', '24', '--limit', '-1'],
      ['--prefix', '24', '--limit', '2.5'],
      ['--prefix', '24', '--growth-percent', '0'],
      ['--prefix', '24', '--additional', '1'],
      ['--prefix', '24', '--basis', 'peak'],
      ['--prefix', '24', '--parent', ''],
    ]) {
      final result = run([...scope, ...options]);
      expect(result.code, 2, reason: '$options: ${result.err}');
      expect(result.err, contains('Usage error:'), reason: '$options');
    }
    final store = InventoryStore.open(database);
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
    store.close();
  });

  test('invalid selected parents and incompatible VCN hierarchy cannot apply',
      () {
    final store = InventoryStore.open(database);
    store.saveAll(const [
      PrefixRecord(
          id: 'vcn',
          cidr: '10.90.0.0/20',
          name: 'VCN',
          routingDomain: 'fictional'),
      PrefixRecord(
          id: 'subnet',
          cidr: '10.91.0.0/24',
          name: 'Subnet',
          routingDomain: 'fictional',
          kind: PrefixKind.subnet),
      PrefixRecord(
          id: 'retired',
          cidr: '10.92.0.0/20',
          name: 'Retired',
          routingDomain: 'fictional',
          status: PrefixStatus.retired),
    ]);
    final before = store.history().length;
    store.close();
    for (final options in [
      [...scope, '--parent', 'missing'],
      [...scope, '--parent', 'vcn', '--kind', 'vcn'],
      [
        '--pool',
        '10.90.0.0/21',
        '--routing-domain',
        'fictional',
        '--parent',
        'vcn'
      ],
      [
        '--pool',
        '10.90.0.0/20',
        '--routing-domain',
        'other',
        '--parent',
        'vcn'
      ],
      [
        '--pool',
        '10.91.0.0/24',
        '--routing-domain',
        'fictional',
        '--parent',
        'subnet'
      ],
      [
        '--pool',
        '10.92.0.0/20',
        '--routing-domain',
        'fictional',
        '--parent',
        'retired'
      ],
    ]) {
      final result =
          run([...options, '--prefix', '26', '--apply', '--name', 'Invalid']);
      expect(result.code, 1, reason: '$options: ${result.err}');
    }
    final reopened = InventoryStore.open(database);
    expect(reopened.list(), hasLength(3));
    expect(reopened.history(), hasLength(before));
    reopened.close();
  });

  test('OCI subnet capacity cannot be used for VCN intent', () {
    final demand = run([
      ...scope,
      '--addresses',
      '10',
      '--growth-percent',
      '0',
      '--kind',
      'vcn'
    ]);
    expect(demand.code, 2, reason: demand.err);
    final prefix = run(
        [...scope, '--prefix', '24', '--policy', 'oci_ipv4', '--kind', 'vcn']);
    expect(prefix.code, 2, reason: prefix.err);
  });

  test('empty aligned candidates can preview but cannot be applied', () {
    final store = InventoryStore.open(database);
    store.save(const PrefixRecord(
        id: 'occupied',
        cidr: '10.90.0.0/20',
        name: 'Occupied',
        routingDomain: 'fictional'));
    final before = store.history().length;
    store.close();
    final preview = run([...scope, '--prefix', '24', '--format', 'json']);
    expect(preview.code, 0, reason: preview.err);
    final plan = jsonDecode(preview.out) as Map<String, dynamic>;
    expect(plan['summary']['freeSlots'], '0');
    expect(plan['candidates'], isEmpty);
    final applied =
        run([...scope, '--prefix', '24', '--apply', '--name', 'No slot']);
    expect(applied.code, 1, reason: applied.err);
    expect(applied.err.toLowerCase(), contains('no aligned'));
    final reopened = InventoryStore.open(database);
    expect(reopened.list(), hasLength(1));
    expect(reopened.history(), hasLength(before));
    reopened.close();
  });

  test('text preview explains its scope and explicit apply requirement', () {
    final result = run([...scope, '--prefix', '24', '--limit', '1']);
    expect(result.code, 0, reason: result.err);
    expect(result.out, contains('fictional'));
    expect(result.out, contains('1 shown of 16'));
    expect(result.out, contains('Available in this inventory'));
    expect(result.out, contains('Preview only'));
    expect(result.out, contains('--apply'));
    final help = run(['--help']);
    expect(help.code, 0);
    expect(help.out, contains('--growth-percent'));
    expect(help.out, contains('--apply'));
  });
}
