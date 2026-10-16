// CIDR Atlas — Multi-region OCI identity and atomic refresh integration tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

Map<String, dynamic> regionalBundle(
    {bool onlyPhoenix = false, bool overlap = false, bool malformed = false}) {
  final regions = ['us-phoenix-1', if (!onlyPhoenix) 'us-ashburn-1'];
  return {
    'metadata': {
      'tenancy': 'ocid1.tenancy.oc1..fictional',
      'regions': regions,
      'regionMode': 'selected',
      'compartmentMode': 'allAccessible',
      'collectedAt': '2026-10-15T18:30:00Z',
      'coverage':
          'Fictional multi-region scoped observation; omitted resources are not deletion.',
    },
    'vcns': [
      for (var i = 0; i < regions.length; i++)
        {
          'id': 'fictional-vcn-identity',
          'display-name': 'Fictional VCN in ${regions[i]}',
          'compartment-id': 'fictional-compartment-$i',
          'region': regions[i],
          'cidr-block': '10.${overlap ? 64 : 64 + i}.0.0/16',
        },
    ],
    'subnets': [
      for (var i = 0; i < regions.length; i++)
        {
          'id': 'fictional-subnet-identity',
          'vcn-id': 'fictional-vcn-identity',
          'compartment-id': 'fictional-child-compartment-$i',
          'region': regions[i],
          'cidr-block':
              '10.${overlap ? 64 : 64 + i}.1.${malformed && i == 1 ? 7 : 0}/24',
        },
    ],
  };
}

void main() {
  late InventoryStore store;
  setUp(() => store = InventoryStore.memory());
  tearDown(() => store.close());

  test(
      'multi-region preview retains actual regions and regional parent identity',
      () {
    final preview = InventoryImport.json(jsonEncode(regionalBundle()),
        routingDomain: 'fictional-connected');
    expect(preview.canApply, isTrue);
    expect(preview.source, 'OCI JSON');
    expect(preview.records, hasLength(4));
    expect(preview.records.map((record) => record.id).toSet(), hasLength(4));
    expect(
        preview.warnings
            .any((warning) => warning.contains('unknown tenancy or region')),
        isFalse);
    for (final child in preview.records
        .where((record) => record.kind == PrefixKind.subnet)) {
      final parent =
          preview.records.singleWhere((record) => record.id == child.parentId);
      expect(parent.region, child.region);
      expect(
          parent.compartment,
          child.region == 'us-phoenix-1'
              ? 'fictional-compartment-0'
              : 'fictional-compartment-1');
      expect(parent.resourceId, child.vcnId);
      expect(Cidr.parse(parent.cidr).contains(Cidr.parse(child.cidr)), isTrue);
    }
    expect(InventoryRules.conflicts(preview.records), isEmpty);
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
  });

  test(
      'multi-region apply and narrower refresh retain planning fields and absent region',
      () {
    final initial = InventoryImport.json(jsonEncode(regionalBundle()),
        routingDomain: 'fictional-connected');
    store.applyImport(initial);
    final originalIds = store.list().map((record) => record.id).toSet();
    final child = store.list().firstWhere((record) =>
        record.kind == PrefixKind.subnet && record.region == 'us-phoenix-1');
    store.save(child.copyWith(
        owner: 'Sergio',
        notes: 'Reserved for fictional growth',
        status: PrefixStatus.reserved,
        environment: 'planned'));
    final refresh = InventoryImport.json(
        jsonEncode(regionalBundle(onlyPhoenix: true)),
        routingDomain: 'fictional-connected',
        existingRecords: store.list());
    expect(refresh.canApply, isTrue);
    store.applyImport(refresh);
    expect(store.list().map((record) => record.id).toSet(), originalIds);
    expect(store.list().where((record) => record.region == 'us-ashburn-1'),
        hasLength(2));
    final updated = store.list().singleWhere((record) => record.id == child.id);
    expect(updated.owner, 'Sergio');
    expect(updated.notes, 'Reserved for fictional growth');
    expect(updated.status, PrefixStatus.reserved);
    expect(updated.environment, 'planned');
    expect(updated.parentId, child.parentId);
    expect(updated.source, 'oci');
    expect(store.history(), hasLength(3));
  });

  test('invalid later regional record prevents all writes and audit changes',
      () {
    store.applyImport(InventoryImport.json(
        jsonEncode(regionalBundle(onlyPhoenix: true)),
        routingDomain: 'fictional-connected'));
    final before =
        jsonEncode(store.list().map((record) => record.toJson()).toList());
    final historyCount = store.history().length;
    final invalid = InventoryImport.json(
        jsonEncode(regionalBundle(malformed: true)),
        routingDomain: 'fictional-connected',
        existingRecords: store.list());
    expect(invalid.canApply, isFalse);
    expect(invalid.errors, isNotEmpty);
    expect(() => store.applyImport(invalid), throwsFormatException);
    expect(jsonEncode(store.list().map((record) => record.toJson()).toList()),
        before);
    expect(store.history(), hasLength(historyCount));
  });

  test('same-domain overlap across regions remains visible after atomic import',
      () {
    final preview = InventoryImport.json(
        jsonEncode(regionalBundle(overlap: true)),
        routingDomain: 'fictional-connected');
    expect(preview.canApply, isTrue);
    store.applyImport(preview);
    final conflicts = InventoryRules.conflicts(store.list());
    expect(conflicts, isNotEmpty);
    expect(
        conflicts
            .any((conflict) => conflict.first.region != conflict.second.region),
        isTrue);
    expect(store.list(), hasLength(4));
  });
}
