// CIDR Atlas
// Upgrade compatibility tests for inventories, backups and CSV exports
// written by v0.3.0: zone-less verifiedAt, legacy region spellings, and
// placeholder VCN parents.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

const _tenancy = 'ocid1.tenancy.oc1..fictional';
const _vcnId = 'ocid1.vcn.oc1.iad.fictional';
const _subnetId = 'ocid1.subnet.oc1.iad.fictional';

/// A v0.3.0 backup: local times were serialized without a zone.
String _legacyBackup(List<String> verifiedAt) => jsonEncode({
      'format': 'cidr-atlas',
      'version': 1,
      'exportedAt': '2026-10-15T09:00:00.000',
      'records': [
        for (var i = 0; i < verifiedAt.length; i++)
          {
            'id': 'manual:$i',
            'cidr': '10.$i.0.0/16',
            'name': 'legacy-$i',
            'routingDomain': 'corp',
            'kind': 'vcn',
            'status': 'reserved',
            'customer': '',
            'tenancy': '',
            'region': '',
            'compartment': '',
            'environment': '',
            'owner': 'team-a',
            'resourceId': '',
            'vcnId': '',
            'parentId': '',
            'notes': '',
            'source': 'manual',
            'verifiedAt': verifiedAt[i],
          },
      ],
    });

Map<String, dynamic> _ashburnBundle({bool withSubnet = true}) => {
      'metadata': {
        'tenancy': _tenancy,
        'region': 'us-ashburn-1',
        'collectedAt': '2026-10-16T08:00:00Z',
      },
      'vcns': [
        {
          'id': _vcnId,
          'display-name': 'prod-vcn',
          'compartment-id': 'ocid1.compartment.oc1..fictional',
          'cidr-block': '10.0.0.0/16',
        },
      ],
      'subnets': [
        if (withSubnet)
          {
            'id': _subnetId,
            'vcn-id': _vcnId,
            'display-name': 'prod-app',
            'compartment-id': 'ocid1.compartment.oc1..fictional',
            'cidr-block': '10.0.1.0/24',
          },
      ],
    };

/// Records as v0.3.0 discovery stored them: the region as typed.
List<PrefixRecord> _legacyOciRecords(String vcnRegion, String subnetRegion) => [
      PrefixRecord(
        id: 'oci:legacy-vcn',
        cidr: '10.0.0.0/16',
        name: 'prod-vcn',
        routingDomain: 'corp',
        kind: PrefixKind.vcn,
        status: PrefixStatus.active,
        tenancy: _tenancy,
        region: vcnRegion,
        resourceId: _vcnId,
        owner: 'network-team',
        notes: 'planned in v0.3.0',
        environment: 'prod',
        source: 'oci',
      ),
      PrefixRecord(
        id: 'oci:legacy-subnet',
        cidr: '10.0.1.0/24',
        name: 'prod-app',
        routingDomain: 'corp',
        kind: PrefixKind.subnet,
        status: PrefixStatus.active,
        tenancy: _tenancy,
        region: subnetRegion,
        resourceId: _subnetId,
        vcnId: _vcnId,
        parentId: 'oci:legacy-vcn',
        owner: 'app-team',
        customer: 'fictional-customer',
        source: 'oci',
      ),
    ];

void main() {
  group('v0.3.0 zone-less verifiedAt', () {
    test('a v0.3.0 backup restores and reads zone-less values as local time',
        () {
      final preview = InventoryImport.json(
        _legacyBackup(['2026-10-15T00:00:00.000', '2026-10-15T10:30:00.000']),
        routingDomain: '',
      );
      expect(preview.errors, isEmpty);
      expect(preview.canApply, isTrue);
      expect(
        preview.records.map((record) => record.verifiedAt),
        [
          DateTime(2026, 10, 15).toUtc(),
          DateTime(2026, 10, 15, 10, 30).toUtc(),
        ],
      );
      expect(
        preview.warnings,
        contains('2 verifiedAt values have no UTC offset and were read as '
            'local time.'),
      );
      final store = InventoryStore.memory();
      addTearDown(store.close);
      store.applyImport(preview);
      expect(store.list().map((record) => record.owner), ['team-a', 'team-a']);
    });

    test('a v0.3.0 CSV export re-imports with one counted warning', () {
      final preview = InventoryImport.csv(
        'id,cidr,name,routingDomain,verifiedAt\r\n'
        'manual:a,10.0.0.0/16,a,corp,2026-10-15T00:00:00.000\r\n'
        'manual:b,10.1.0.0/16,b,corp,2026-10-15T18:30:00.000Z\r\n',
      );
      expect(preview.errors, isEmpty);
      expect(preview.records.first.verifiedAt, DateTime(2026, 10, 15).toUtc());
      expect(
        preview.records.last.verifiedAt,
        DateTime.utc(2026, 10, 15, 18, 30),
      );
      expect(
        preview.warnings,
        contains('1 verifiedAt value has no UTC offset and was read as local '
            'time.'),
      );
    });

    test('zoned values add no local-time warning', () {
      final preview = InventoryImport.json(
        _legacyBackup(['2026-10-15T00:00:00.000Z']),
        routingDomain: '',
      );
      expect(preview.errors, isEmpty);
      expect(
        preview.warnings.where((warning) => warning.contains('UTC offset')),
        isEmpty,
      );
    });

    test('calendar rollover and garbage stay rejected', () {
      for (final value in [
        '2026-02-30T00:00:00.000',
        '2026-10-15T24:00:00.000',
        '2026-02-30T00:00:00Z',
        'yesterday',
      ]) {
        final backup = InventoryImport.json(
          _legacyBackup([value]),
          routingDomain: '',
        );
        expect(backup.canApply, isFalse, reason: value);
        expect(backup.errors.single, startsWith('Backup record 1: '));
        expect(backup.errors.single, contains('verifiedAt "$value"'));
        final csv = InventoryImport.csv(
          'cidr,name,routingDomain,verifiedAt\n10.0.0.0/16,x,corp,$value\n',
        );
        expect(csv.canApply, isFalse, reason: value);
        expect(csv.errors.single, contains('verifiedAt "$value"'));
      }
    });
  });

  group('v0.3.0 region spellings', () {
    for (final (vcnRegion, subnetRegion) in [
      ('IAD', 'IAD'),
      ('US-ASHBURN-1', 'US-ASHBURN-1'),
    ]) {
      test('a refresh with us-ashburn-1 updates $vcnRegion records in place',
          () {
        final store = InventoryStore.memory();
        addTearDown(store.close);
        store.saveAll(_legacyOciRecords(vcnRegion, subnetRegion));
        final preview = InventoryImport.json(
          jsonEncode(_ashburnBundle()),
          routingDomain: 'corp',
          existingRecords: store.list(),
        );
        expect(preview.errors, isEmpty);
        store.applyImport(preview);

        final records = {for (final r in store.list()) r.id: r};
        expect(records.keys, {'oci:legacy-vcn', 'oci:legacy-subnet'});
        final vcn = records['oci:legacy-vcn']!;
        final subnet = records['oci:legacy-subnet']!;
        expect(vcn.region, 'us-ashburn-1');
        expect(subnet.region, 'us-ashburn-1');
        expect(vcn.owner, 'network-team');
        expect(vcn.notes, 'planned in v0.3.0');
        expect(vcn.environment, 'prod');
        expect(subnet.owner, 'app-team');
        expect(subnet.customer, 'fictional-customer');
        expect(subnet.parentId, 'oci:legacy-vcn');
        expect(vcn.verifiedAt, DateTime.utc(2026, 10, 16, 8));
        expect(InventoryRules.conflicts(store.list()), isEmpty);
      });
    }

    test('a VCN-only refresh carries the region to its unobserved subnet', () {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      store.saveAll(_legacyOciRecords('IAD', 'IAD'));
      final preview = InventoryImport.json(
        jsonEncode(_ashburnBundle(withSubnet: false)),
        routingDomain: 'corp',
        existingRecords: store.list(),
      );
      expect(preview.errors, isEmpty);
      store.applyImport(preview);
      final records = {for (final r in store.list()) r.id: r};
      expect(records, hasLength(2));
      expect(records['oci:legacy-vcn']!.region, 'us-ashburn-1');
      expect(records['oci:legacy-subnet']!.region, 'us-ashburn-1');
      expect(records['oci:legacy-subnet']!.owner, 'app-team');
    });
  });

  test('a subnet-only refresh carries the region to its unobserved VCN', () {
    final store = InventoryStore.memory();
    addTearDown(store.close);
    store.saveAll(_legacyOciRecords('IAD', 'IAD'));
    final bundle = _ashburnBundle()..['vcns'] = <dynamic>[];
    final preview = InventoryImport.json(
      jsonEncode(bundle),
      routingDomain: 'corp',
      existingRecords: store.list(),
    );
    expect(preview.errors, isEmpty);
    store.applyImport(preview);
    final records = {for (final r in store.list()) r.id: r};
    expect(records, hasLength(2));
    expect(records['oci:legacy-vcn']!.region, 'us-ashburn-1');
    expect(records['oci:legacy-vcn']!.owner, 'network-team');
    expect(records['oci:legacy-subnet']!.region, 'us-ashburn-1');
    expect(records['oci:legacy-subnet']!.parentId, 'oci:legacy-vcn');
  });

  group('v0.3.0 placeholder VCN parent', () {
    test('an OCI refresh that records the real VCN applies with an advisory',
        () {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      store.saveAll([
        PrefixRecord(
          id: 'plan-vcn',
          cidr: '10.0.0.0/16',
          name: 'planned-vcn',
          routingDomain: 'corp',
          kind: PrefixKind.vcn,
        ),
        PrefixRecord(
          id: 'plan-sub',
          cidr: '10.0.1.0/24',
          name: 'planned-app',
          routingDomain: 'corp',
          kind: PrefixKind.subnet,
          parentId: 'plan-vcn',
          vcnId: _vcnId,
          owner: 'app-team',
        ),
      ]);
      final preview = InventoryImport.json(
        jsonEncode(_ashburnBundle(withSubnet: false)),
        routingDomain: 'corp',
        existingRecords: store.list(),
      );
      expect(preview.errors, isEmpty);
      expect(preview.canApply, isTrue);
      expect(
        preview.warnings,
        contains(
          'Subnet planned-app (10.0.1.0/24) has vcnId $_vcnId, which names '
          'VCN prod-vcn (10.0.0.0/16, $_vcnId), but its parent is the '
          'placeholder VCN planned-vcn (10.0.0.0/16) without a resource id. '
          'Clear or change the parent of planned-app.',
        ),
      );
      store.applyImport(preview);
      final records = {for (final r in store.list()) r.id: r};
      expect(records, hasLength(3));
      expect(records['plan-sub']!.parentId, 'plan-vcn');
      expect(records['plan-sub']!.owner, 'app-team');
      expect(InventoryRules.advisories(store.list()), hasLength(1));

      // Later writes are not blocked by the advisory.
      store.save(
        PrefixRecord(
          id: 'other',
          cidr: '10.9.0.0/16',
          name: 'other',
          routingDomain: 'corp',
        ),
      );
      store.save(records['plan-sub']!.copyWith(parentId: ''));
      expect(InventoryRules.advisories(store.list()), isEmpty);
    });
  });
}
