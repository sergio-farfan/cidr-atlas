// CIDR Atlas: durable inventory storage, reconciliation, and atomic imports.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'import_test.dart' show ociBundle, vcn, subnet;

PrefixRecord record(
  String id,
  String cidr, {
  String parentId = '',
  PrefixKind kind = PrefixKind.vcn,
}) =>
    PrefixRecord(
      id: id,
      cidr: cidr,
      name: id,
      routingDomain: 'corp',
      parentId: parentId,
      kind: kind,
    );

void main() {
  late InventoryStore store;
  setUp(() => store = InventoryStore.memory());
  tearDown(() => store.close());

  test('saves, updates, deletes and records durable audit events', () {
    store.save(record('x', '10.0.0.0/16'));
    store.save(record('x', '10.0.0.0/16').copyWith(owner: 'Sergio'));
    expect(store.list().single.owner, 'Sergio');
    expect(store.history(), hasLength(2));
    store.delete('x');
    expect(store.list(), isEmpty);
    expect(store.history().first.action, 'delete');
    expect(store.history().first.at.isUtc, isTrue);
  });

  test('overlapping prefixes may be saved for review', () {
    store.saveAll([record('x', '10.0.0.0/16'), record('y', '10.0.0.0/24')]);
    expect(store.list(), hasLength(2));
    expect(InventoryRules.conflicts(store.list()), hasLength(1));
  });

  test('bulk save validates entire combined inventory atomically', () {
    store.save(record('existing', '192.168.0.0/16'));
    expect(
      () => store.saveAll([
        record('good', '10.0.0.0/16'),
        record('bad', '10.4.1.1/24'),
      ]),
      throwsFormatException,
    );
    expect(store.list().map((record) => record.id), ['existing']);
    expect(store.history(), hasLength(1));
  });

  test('parents and children can be inserted in a single atomic save', () {
    store.saveAll([
      record(
        'child',
        '10.0.1.0/24',
        parentId: 'parent',
        kind: PrefixKind.subnet,
      ),
      record('parent', '10.0.0.0/16'),
    ]);
    expect(store.list(), hasLength(2));
    expect(InventoryRules.conflicts(store.list()), isEmpty);
  });

  test(
      'deleting referenced parent and shrinking parent both fail without mutation',
      () {
    store.saveAll([
      record('parent', '10.0.0.0/16'),
      record(
        'child',
        '10.0.8.0/24',
        parentId: 'parent',
        kind: PrefixKind.subnet,
      ),
    ]);
    expect(() => store.delete('parent'), throwsFormatException);
    expect(
      () => store.save(record('parent', '10.0.0.0/24')),
      throwsFormatException,
    );
    expect(
      store.list().firstWhere((r) => r.id == 'parent').cidr,
      '10.0.0.0/16',
    );
    expect(store.history(), hasLength(1));
  });

  test('bulk save rejects duplicate input ids', () {
    expect(
      () => store.saveAll([
        record('x', '10.0.0.0/16'),
        record('x', '10.1.0.0/16'),
      ]),
      throwsFormatException,
    );
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
  });

  test('invalid preview cannot partially apply', () {
    final preview = InventoryImport.csv(
      'cidr,name,routingDomain\n10.0.0.0/16,good,corp\n10.1.1.1/24,bad,corp',
    );
    expect(() => store.applyImport(preview), throwsFormatException);
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
  });

  test(
    'apply validates against existing records and rolls back invalid structure',
    () {
      store.saveAll([
        record('parent', '10.0.0.0/16'),
        record(
          'child',
          '10.0.8.0/24',
          parentId: 'parent',
          kind: PrefixKind.subnet,
        ),
      ]);
      final preview = InventoryImport.csv(
        'id,cidr,name,routingDomain\nparent,10.9.0.0/16,renamed,corp',
      );
      expect(preview.canApply, isTrue);
      expect(() => store.applyImport(preview), throwsFormatException);
      expect(
        store.list().firstWhere((r) => r.id == 'parent').cidr,
        '10.0.0.0/16',
      );
      expect(store.history(), hasLength(1));
    },
  );

  test(
      'OCI refresh preserves planning metadata and never removes missing resources',
      () {
    final preview = InventoryImport.json(
      jsonEncode(ociBundle()),
      routingDomain: 'corp',
    );
    expect(preview.errors, isEmpty);
    store.applyImport(preview);
    final original = store.list().first;
    store.save(
      original.copyWith(
        owner: 'Architect',
        notes: 'Keep private',
        status: PrefixStatus.reserved,
        environment: 'prod',
        customer: 'Client',
      ),
    );
    store.save(record('unrelated', '172.16.0.0/16'));
    store.applyImport(preview);
    final refreshed = store.list().firstWhere((r) => r.id == original.id);
    expect(refreshed.owner, 'Architect');
    expect(refreshed.notes, 'Keep private');
    expect(refreshed.status, PrefixStatus.reserved);
    expect(refreshed.environment, 'prod');
    expect(refreshed.customer, 'Client');
    expect(refreshed.parentId, original.parentId);
    expect(store.list(), hasLength(6));
    expect(
      store.history().first.summary,
      contains('absent records were retained'),
    );
    expect(store.history().first.summary, contains('selected compartment'));
  });

  test('OCI alias refresh preserves planning fields and absent prefixes', () {
    final initial = InventoryImport.json(
      jsonEncode(ociBundle(
        vcns: [
          {
            ...vcn,
            'byoipv6CidrBlocks': ['2001:db8:41::/56']
          },
        ],
        subnets: [
          {
            ...subnet,
            'ipv4CidrBlocks': ['10.40.3.0/24']
          },
        ],
      )),
      routingDomain: 'corp',
    );
    store.applyImport(initial);
    final originalSubnet = store.list().firstWhere(
          (record) =>
              record.kind == PrefixKind.subnet && record.cidr == '10.40.2.0/24',
        );
    store.save(originalSubnet.copyWith(
      owner: 'Architect',
      customer: 'Fictional client',
      environment: 'prod',
      notes: 'Keep this plan',
      status: PrefixStatus.planned,
    ));

    final refreshed = InventoryImport.json(
      jsonEncode(ociBundle(
        vcns: [
          {
            ...vcn,
            'byoipv6CidrBlocks': ['2001:db8:42::/56'],
          },
        ],
        subnets: [
          {
            ...subnet,
            'ipv4CidrBlocks': ['10.40.4.0/24'],
          },
        ],
      )),
      routingDomain: 'corp',
    );
    expect(refreshed.canApply, isTrue, reason: refreshed.errors.join('; '));
    store.applyImport(refreshed);

    final preserved =
        store.list().singleWhere((record) => record.id == originalSubnet.id);
    expect(preserved.owner, 'Architect');
    expect(preserved.customer, 'Fictional client');
    expect(preserved.environment, 'prod');
    expect(preserved.notes, 'Keep this plan');
    expect(preserved.status, PrefixStatus.planned);
    expect(store.list().map((record) => record.cidr),
        contains('2001:db8:40::/56'));
    expect(store.list().map((record) => record.cidr),
        contains('2001:db8:41::/56'));
    expect(store.list().map((record) => record.cidr),
        contains('2001:db8:42::/56'));
    expect(store.list().map((record) => record.cidr), contains('10.40.3.0/24'));
    expect(store.list().map((record) => record.cidr), contains('10.40.4.0/24'));
  });

  test('invalid OCI alias CIDR rolls back the entire import atomically', () {
    final preview = InventoryImport.json(
      jsonEncode(ociBundle(vcns: [
        {
          ...vcn,
          'byoipv6-cidr-blocks': ['2001:db8:41::1/56'],
        },
      ])),
      routingDomain: 'corp',
    );

    expect(preview.canApply, isFalse);
    expect(preview.errors.join(), contains('Host bits'));
    expect(() => store.applyImport(preview), throwsFormatException);
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
  });

  test(
    'backup import merges exact records rather than erasing planned ownership',
    () {
      final original = record('x', '10.0.0.0/16').copyWith(
        source: 'oci',
        owner: 'Restored',
        status: PrefixStatus.planned,
      );
      store.save(original.copyWith(owner: 'Old', status: PrefixStatus.active));
      final backup = InventoryImport.json(
        InventoryImport.exportJson([original]),
        routingDomain: '',
      );
      store.applyImport(backup);
      expect(store.list().single.toJson(), original.toJson());
    },
  );

  test('OCI natural identity preserves manual ids and remaps new child parents',
      () {
    final preview =
        InventoryImport.json(jsonEncode(ociBundle()), routingDomain: 'corp');
    final importedVcn =
        preview.records.firstWhere((r) => r.cidr == '10.40.0.0/16');
    store.save(importedVcn.copyWith(
        id: 'manual-production-vcn',
        owner: 'Architect',
        notes: 'Reviewed',
        status: PrefixStatus.planned,
        tenancy: '',
        region: ''));
    final proposed = store.mergedImportRecords(preview);
    expect(store.list(), hasLength(1), reason: 'Preview must not write');
    expect(store.history(), hasLength(1));
    expect(proposed, hasLength(5));
    final mergedVcn =
        proposed.singleWhere((r) => r.id == 'manual-production-vcn');
    expect(mergedVcn.owner, 'Architect');
    expect(mergedVcn.status, PrefixStatus.planned);
    expect(mergedVcn.tenancy, 'ocid1.tenancy.oc1.example');
    expect(proposed.singleWhere((r) => r.cidr == '10.40.2.0/24').parentId,
        'manual-production-vcn');
    expect(InventoryRules.validate(proposed), isEmpty);
    store.applyImport(preview);
    expect(store.list().map((r) => r.toJson()).toList(),
        unorderedEquals(proposed.map((r) => r.toJson()).toList()));
  });

  test('OCI natural identity does not fold independent routing domains', () {
    final input = jsonEncode(ociBundle(subnets: []));
    store.applyImport(InventoryImport.json(input, routingDomain: 'first'));
    store.applyImport(InventoryImport.json(input, routingDomain: 'second'));
    expect(store.list(), hasLength(6));
    expect(InventoryRules.conflicts(store.list()), isEmpty);
  });

  test('ambiguous existing OCI identities fail atomically', () {
    final preview = InventoryImport.json(jsonEncode(ociBundle(subnets: [])),
        routingDomain: 'corp');
    final original = preview.records.first;
    store.saveAll(
        [original.copyWith(id: 'manual-a'), original.copyWith(id: 'manual-b')]);
    expect(() => store.mergedImportRecords(preview), throwsFormatException);
    expect(() => store.applyImport(preview), throwsFormatException);
    expect(store.list(), hasLength(2));
    expect(store.history(), hasLength(1));
  });

  test('partial raw refresh keeps known observed provenance', () {
    store.applyImport(InventoryImport.json(jsonEncode(ociBundle(subnets: [])),
        routingDomain: 'corp'));
    final raw = {...vcn}..remove('compartment-id');
    store.applyImport(InventoryImport.json(
        jsonEncode({
          'data': [raw]
        }),
        routingDomain: 'corp'));
    expect(store.list(), hasLength(3));
    for (final item in store.list()) {
      expect(item.tenancy, 'ocid1.tenancy.oc1.example');
      expect(item.region, 'us-phoenix-1');
      expect(item.compartment, 'ocid1.compartment.oc1.example');
      expect(item.verifiedAt, DateTime.utc(2026, 10, 15, 18, 30));
    }
  });

  test('child-only CSV and backup validate against existing parent context',
      () {
    store.save(record('parent', '10.0.0.0/16'));
    const childCsv =
        'id,cidr,name,routingDomain,kind,parentId\nchild,10.0.1.0/24,Child,corp,subnet,parent';
    expect(InventoryImport.csv(childCsv).canApply, isFalse);
    final csvPreview =
        InventoryImport.csv(childCsv, existingRecords: store.list());
    expect(csvPreview.canApply, isTrue);
    store.applyImport(csvPreview);
    expect(store.list(), hasLength(2));
    final child = record('child', '10.0.1.0/24',
        parentId: 'parent', kind: PrefixKind.subnet);
    final backup = InventoryImport.json(InventoryImport.exportJson([child]),
        routingDomain: '', existingRecords: store.list());
    expect(backup.canApply, isTrue);
  });

  test(
      'raw subnet-only import links existing VCN and inherits allocation ancestry',
      () {
    final vcnPreview = InventoryImport.json(jsonEncode(ociBundle(subnets: [])),
        routingDomain: 'corp');
    final parent =
        record('allocation', '10.0.0.0/8', kind: PrefixKind.allocation);
    store.saveAll([
      parent,
      vcnPreview.records
          .firstWhere((r) => r.cidr == '10.40.0.0/16')
          .copyWith(parentId: parent.id)
    ]);
    final rawSubnet = {...subnet}..remove('ipv6-cidr-block');
    final preview = InventoryImport.json(
        jsonEncode({
          'data': [rawSubnet]
        }),
        routingDomain: 'corp',
        existingRecords: store.list());
    expect(preview.canApply, isTrue);
    store.applyImport(preview);
    final child = store.list().singleWhere((r) => r.kind == PrefixKind.subnet);
    expect(child.parentId, isNotEmpty);
    expect(child.tenancy, 'ocid1.tenancy.oc1.example');
    expect(child.region, 'us-phoenix-1');
    expect(InventoryRules.conflicts(store.list()), isEmpty);
  });

  test(
      'save rejects new conflicts atomically without blocking unrelated safe reservations',
      () {
    store.saveAll([record('x', '10.0.0.0/16'), record('y', '10.0.0.0/24')]);
    expect(
        () =>
            store.save(record('unsafe', '10.0.8.0/24'), rejectConflicts: true),
        throwsA(isA<InventoryConflictException>()));
    expect(store.list(), hasLength(2));
    expect(store.history(), hasLength(1));
    store.save(record('safe', '172.20.0.0/16'), rejectConflicts: true);
    expect(store.list(), hasLength(3));
  });

  test('two database connections recheck reservations inside write transaction',
      () {
    final directory =
        Directory.systemTemp.createTempSync('cidr-atlas-atomic-reserve-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/inventory.sqlite';
    final first = InventoryStore.open(path);
    final second = InventoryStore.open(path);
    addTearDown(first.close);
    addTearDown(second.close);
    expect(first.list(), isEmpty);
    expect(second.list(), isEmpty);
    first.save(record('one', '10.0.0.0/16'), rejectConflicts: true);
    expect(
        () => second.save(record('two', '10.0.0.0/24'), rejectConflicts: true),
        throwsA(isA<InventoryConflictException>()));
    expect(first.list(), hasLength(1));
    expect(first.history(), hasLength(1));
  });

  test('history limit and no-op writes behave predictably', () {
    store.saveAll([]);
    store.delete('absent');
    expect(store.history(), isEmpty);
    store.save(record('x', '10.0.0.0/16'));
    store.save(record('y', '10.1.0.0/16'));
    expect(store.history(limit: 1), hasLength(1));
    expect(store.history(limit: 0), isEmpty);
    expect(() => store.history(limit: -1), throwsArgumentError);
  });

  test('database persists across reopen and uses schema version 1', () {
    final directory = Directory.systemTemp.createTempSync('cidr-atlas-store-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/nested/inventory.sqlite';
    var disk = InventoryStore.open(path);
    disk.save(record('x', '10.0.0.0/16'));
    disk.close();
    disk = InventoryStore.open(path);
    expect(disk.list().single.id, 'x');
    expect(disk.history(), hasLength(1));
    disk.close();
    final database = sqlite3.open(path);
    expect(database.select('PRAGMA user_version').first.values.first, 1);
    database.dispose();
  });

  test('database from newer app version is rejected', () {
    final directory = Directory.systemTemp.createTempSync(
      'cidr-atlas-version-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/inventory.sqlite';
    final database = sqlite3.open(path);
    database.execute('PRAGMA user_version = 99');
    database.dispose();
    expect(() => InventoryStore.open(path), throwsStateError);
  });

  test('close is idempotent and use after close is readable', () {
    store.close();
    store.close();
    expect(() => store.list(), throwsStateError);
  });
}
