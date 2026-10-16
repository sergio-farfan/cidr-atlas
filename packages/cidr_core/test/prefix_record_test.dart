// CIDR Atlas
// Prefix metadata serialization and validation tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:test/test.dart';

void main() {
  test('all metadata and dates round-trip through portable JSON', () {
    final record = PrefixRecord(
      id: 'prefix-1',
      cidr: '10.0.0.0/16',
      name: 'Production',
      routingDomain: 'corporate',
      kind: PrefixKind.vcn,
      status: PrefixStatus.active,
      customer: 'Acme',
      tenancy: 'tenancy-1',
      region: 'us-phoenix-1',
      compartment: 'network',
      environment: 'prod',
      owner: 'Sergio',
      resourceId: 'ocid1.vcn.example',
      vcnId: '',
      parentId: 'allocation-1',
      notes: 'Review connectivity',
      source: 'manual',
      verifiedAt: DateTime.utc(2026, 10, 15, 20),
    );
    final restored = PrefixRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), record.toJson());
    expect(record.copyWith(name: 'Updated').verifiedAt, record.verifiedAt);
    expect(record.copyWith(verifiedAt: null).verifiedAt, isNull);
    expect(record.copyWith(owner: '').owner, isEmpty);
    expect(record.name, 'Production');
  });

  test('missing optional metadata has stable defaults', () {
    final record = PrefixRecord.fromJson({
      'id': '1',
      'cidr': '::/0',
      'name': 'IPv6',
      'routingDomain': 'test',
    });
    expect(record.kind, PrefixKind.vcn);
    expect(record.status, PrefixStatus.reserved);
    expect(record.customer, isEmpty);
    expect(record.verifiedAt, isNull);
  });

  test(
    'rejects malformed record fields rather than changing their meaning',
    () {
      final valid = {
        'id': '1',
        'cidr': '::/0',
        'name': 'IPv6',
        'routingDomain': 'test',
      };
      expect(
        () => PrefixRecord.fromJson({...valid, 'kind': 'cluster'}),
        throwsFormatException,
      );
      expect(
        () => PrefixRecord.fromJson({...valid, 'status': 'approved'}),
        throwsFormatException,
      );
      expect(
        () => PrefixRecord.fromJson({...valid, 'id': 123}),
        throwsFormatException,
      );
      expect(
        () => PrefixRecord.fromJson({...valid, 'verifiedAt': 'yesterday'}),
        throwsFormatException,
      );
      expect(() => PrefixRecord.fromJson({}), throwsFormatException);
    },
  );
}
