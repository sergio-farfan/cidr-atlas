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

  group('observation time', () {
    test('parseObservationTime requires an explicit zone and returns UTC', () {
      final offset = parseObservationTime('2026-10-15T20:30:00.123+02:00');
      expect(offset.isUtc, isTrue);
      expect(offset, DateTime.utc(2026, 10, 15, 18, 30, 0, 123));
      expect(
        parseObservationTime('2026-10-15T13:30-05:00'),
        DateTime.utc(2026, 10, 15, 18, 30),
      );
      expect(
        parseObservationTime('2026-10-15T18:30:00.000123Z'),
        DateTime.utc(2026, 10, 15, 18, 30, 0, 0, 123),
      );
      expect(
        parseObservationTime('2026-10-15T18:30:00.1234567Z'),
        DateTime.utc(2026, 10, 15, 18, 30, 0, 123, 456),
      );
      expect(parseObservationTime('2024-02-29T00:00:00Z'),
          DateTime.utc(2024, 2, 29));
      for (final value in [
        '2026-10-16 12:00',
        '2026-10-15T10:00:00',
        '2026-10-15',
        '2026-13-45',
        '2026-13-45T00:00:00Z',
        '2026-02-30T00:00:00Z',
        '2026-02-29T00:00:00Z',
        '2026-10-15T24:00:00Z',
        '2026-10-15T23:60:00Z',
        '2026-10-15T23:59:60Z',
        '2026-10-15T18:30:00+24:00',
        '2026-10-15T18:30:00+0200',
        '20261015T183000Z',
        'yesterday',
        '',
      ]) {
        expect(() => parseObservationTime(value), throwsFormatException,
            reason: value);
      }
    });

    test('fromJson rejects calendar rollover and keeps zoned values in UTC',
        () {
      const valid = {
        'id': '1',
        'cidr': '10.0.0.0/16',
        'name': 'x',
        'routingDomain': 'test',
      };
      for (final value in [
        '2026-13-45',
        '2026-02-30T00:00:00Z',
        '2026-10-15T24:00:00.000Z',
        '2026-10-15T23:59:60',
      ]) {
        expect(() => PrefixRecord.fromJson({...valid, 'verifiedAt': value}),
            throwsFormatException,
            reason: value);
      }
      final zoned = PrefixRecord.fromJson(
          {...valid, 'verifiedAt': '2026-10-15T20:30:00.000+02:00'});
      expect(zoned.verifiedAt, DateTime.utc(2026, 10, 15, 18, 30));
    });

    test('zone-less stored values keep their legacy local meaning', () {
      // Older versions serialized local DateTimes without a zone.
      final local = DateTime(2026, 10, 15, 10);
      final restored = PrefixRecord.fromJson({
        'id': '1',
        'cidr': '10.0.0.0/16',
        'name': 'x',
        'routingDomain': 'test',
        'verifiedAt': local.toIso8601String(),
      });
      expect(restored.verifiedAt!.isAtSameMomentAs(local), isTrue);
      // Writing normalizes to UTC so the instant survives a time-zone change.
      final written = restored.toJson()['verifiedAt'] as String;
      expect(written, endsWith('Z'));
      expect(written, local.toUtc().toIso8601String());
      expect(parseObservationTime(written).isAtSameMomentAs(local), isTrue);
    });
  });
}
