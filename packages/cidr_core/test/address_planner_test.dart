// CIDR Atlas
// Exact capacity, availability, and allocation recommendation tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:test/test.dart';

PrefixRecord record(
  String id,
  String cidr, {
  PrefixKind kind = PrefixKind.vcn,
  PrefixStatus status = PrefixStatus.reserved,
  String domain = 'corporate',
  String parentId = '',
}) =>
    PrefixRecord(
        id: id,
        cidr: cidr,
        name: id,
        routingDomain: domain,
        kind: kind,
        status: status,
        parentId: parentId);

void main() {
  group('CIDR details', () {
    test('IPv4 masks and inclusive ranges include all mathematical addresses',
        () {
      final details = CidrDetails.from(Cidr.parse('192.0.2.128/25'));
      expect(details.hostBits, 7);
      expect(details.totalAddresses, BigInt.from(128));
      expect(details.firstAddress, '192.0.2.128');
      expect(details.lastAddress, '192.0.2.255');
      expect(details.subnetMask, '255.255.255.128');
      expect(details.assignableAddresses, isNull);
      expect(details.containingSupernet(24).canonical, '192.0.2.0/24');
      expect(details.containingSupernet(0).canonical, '0.0.0.0/0');
      expect(details.containingSupernet(25), details.cidr);
      expect(() => details.containingSupernet(26), throwsRangeError);
      expect(() => details.containingSupernet(-1), throwsRangeError);
    });

    test('IPv4 /0 /31 /32 retain raw capacity without broadcast assumptions',
        () {
      final cases = [
        ('0.0.0.0/0', '4294967296', '0.0.0.0', '255.255.255.255', '0.0.0.0'),
        (
          '192.0.2.254/31',
          '2',
          '192.0.2.254',
          '192.0.2.255',
          '255.255.255.254'
        ),
        (
          '255.255.255.255/32',
          '1',
          '255.255.255.255',
          '255.255.255.255',
          '255.255.255.255'
        ),
      ];
      for (final (cidr, capacity, first, last, mask) in cases) {
        final details = CidrDetails.from(Cidr.parse(cidr));
        expect(details.totalAddresses.toString(), capacity);
        expect(details.firstAddress, first);
        expect(details.lastAddress, last);
        expect(details.subnetMask, mask);
      }
    });

    test('IPv6 /0 and /128 stay exact and containing supernets align', () {
      final all = CidrDetails.from(Cidr.parse('::/0'));
      expect(all.totalAddresses.toString(),
          '340282366920938463463374607431768211456');
      expect(all.firstAddress, '::');
      expect(all.lastAddress, 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff');
      expect(all.subnetMask, isNull);
      final last = CidrDetails.from(
          Cidr.parse('ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128'));
      expect(last.totalAddresses, BigInt.one);
      expect(last.firstAddress, last.lastAddress);
      expect(last.containingSupernet(64).canonical, 'ffff:ffff:ffff:ffff::/64');
      expect(jsonDecode(jsonEncode(all.toJson()))['totalAddresses'],
          '340282366920938463463374607431768211456');
    });

    test('OCI IPv4 eligible subnet counts reserve first two and final address',
        () {
      final details = CidrDetails.from(Cidr.parse('192.0.2.128/25'),
          policy: AddressPolicy.ociIpv4Subnet);
      expect(details.assignableAddresses, BigInt.from(125));
      expect(details.assignableFirst, '192.0.2.130');
      expect(details.assignableLast, '192.0.2.254');
      expect(
          CidrDetails.from(Cidr.parse('10.0.0.0/16'),
                  policy: AddressPolicy.ociIpv4Subnet)
              .assignableAddresses,
          BigInt.from(65533));
      expect(
          CidrDetails.from(Cidr.parse('192.0.2.252/30'),
                  policy: AddressPolicy.ociIpv4Subnet)
              .assignableFirst,
          '192.0.2.254');
      expect(
          CidrDetails.from(Cidr.parse('192.0.2.252/30'),
                  policy: AddressPolicy.ociIpv4Subnet)
              .assignableLast,
          '192.0.2.254');
    });

    test(
        'ineligible provider prefixes keep raw details without assignable count',
        () {
      for (final text in [
        '10.0.0.0/15',
        '192.0.2.0/31',
        '192.0.2.0/32',
        '2001:db8::/64'
      ]) {
        final details = CidrDetails.from(Cidr.parse(text),
            policy: AddressPolicy.ociIpv4Subnet);
        expect(details.totalAddresses, greaterThan(BigInt.zero));
        expect(details.assignableAddresses, isNull);
        expect(details.assignableFirst, isNull);
        expect(details.assignableLast, isNull);
        expect(details.policyNote, isNotEmpty);
      }
    });
  });

  group('address demand', () {
    test('ceiling growth plus additional demand remains exact for peak inputs',
        () {
      final demand = AddressDemand(
          addresses: BigInt.from(100),
          growthPercent: 20,
          additionalAddresses: BigInt.from(4));
      expect(demand.targetAddresses, BigInt.from(124));
      final rounded = AddressDemand(
          addresses: BigInt.from(101),
          growthPercent: 1,
          basis: DemandBasis.peak);
      expect(rounded.targetAddresses, BigInt.from(103));
      expect(rounded.additionalAddresses, BigInt.zero);
      expect(rounded.basis, DemandBasis.peak);
      expect(
          AddressDemand(
                  addresses: BigInt.parse('9007199254740993'), growthPercent: 0)
              .targetAddresses
              .toString(),
          '9007199254740993');
    });

    test('invalid address demand is rejected before sizing', () {
      expect(() => AddressDemand(addresses: BigInt.zero, growthPercent: 0),
          throwsArgumentError);
      expect(() => AddressDemand(addresses: -BigInt.one, growthPercent: 0),
          throwsArgumentError);
      expect(() => AddressDemand(addresses: BigInt.one, growthPercent: -1),
          throwsArgumentError);
      expect(
          () => AddressDemand(
              addresses: BigInt.one,
              growthPercent: 0,
              additionalAddresses: -BigInt.one),
          throwsArgumentError);
    });
  });

  group('exact address space', () {
    test(
        'fragmented totals and candidates match an exhaustive small-pool oracle',
        () {
      final parent = Cidr.parse('192.0.2.0/24');
      for (var seed = 0; seed < 24; seed++) {
        final occupied = List<bool>.filled(256, false);
        final records = <PrefixRecord>[];
        for (var i = 0; i < 12; i++) {
          final size = 1 << ((seed + i) % 6);
          final offset = (((seed * 19 + i * 31) % 256) ~/ size) * size;
          final domain = i % 5 == 0 ? 'separate' : 'corporate';
          final retired = i % 7 == 0;
          records.add(record(
              'block-$i', '192.0.2.$offset/${32 - ((seed + i) % 6)}',
              domain: domain,
              status: retired ? PrefixStatus.retired : PrefixStatus.reserved));
          if (domain == 'corporate' && !retired) {
            for (var address = offset; address < offset + size; address++) {
              occupied[address] = true;
            }
          }
        }
        for (var prefix = 26; prefix <= 32; prefix++) {
          final size = 1 << (32 - prefix);
          final expected = <String>[];
          for (var offset = 0; offset < 256; offset += size) {
            if (!occupied.skip(offset).take(size).any((value) => value)) {
              expected.add('192.0.2.$offset/$prefix');
            }
          }
          final plan = AddressPlanner.plan(
              parent: parent,
              routingDomain: 'corporate',
              prefixLength: prefix,
              records: records,
              limit: 256);
          expect(plan.summary.freeAddresses,
              BigInt.from(occupied.where((value) => !value).length),
              reason: 'seed $seed /$prefix raw');
          expect(plan.summary.freeSlots, BigInt.from(expected.length),
              reason: 'seed $seed /$prefix slots');
          expect(plan.candidates.map((candidate) => candidate.cidr.canonical),
              unorderedEquals(expected),
              reason: 'seed $seed /$prefix candidates');
          expect(plan.summary.freeAddresses + plan.summary.blockedAddresses,
              BigInt.from(256));
        }
      }
    });

    test('inclusive intervals format boundaries and reject malformed ranges',
        () {
      final range = AddressInterval(
          start: BigInt.from(3221225984),
          end: BigInt.from(3221226239),
          version: 4);
      expect(range.addressCount, BigInt.from(256));
      expect(range.firstAddress, '192.0.2.0');
      expect(range.lastAddress, '192.0.2.255');
      expect(
          () =>
              AddressInterval(start: BigInt.one, end: BigInt.zero, version: 4),
          throwsArgumentError);
      expect(
          () =>
              AddressInterval(start: -BigInt.one, end: BigInt.one, version: 4),
          throwsArgumentError);
      expect(
          () => AddressInterval(
              start: BigInt.zero, end: BigInt.one << 32, version: 4),
          throwsArgumentError);
      expect(
          () =>
              AddressInterval(start: BigInt.zero, end: BigInt.one, version: 5),
          throwsArgumentError);
    });

    test(
        'unions blockers without double counting and counts only complete slots',
        () {
      final plan = AddressPlanner.plan(
          parent: Cidr.parse('192.0.2.0/24'),
          routingDomain: 'corporate',
          prefixLength: 27,
          limit: 1,
          records: [
            record('one', '192.0.2.1/32'),
            record('nested', '192.0.2.64/28'),
            record('larger', '192.0.2.64/26'),
            record('duplicate', '192.0.2.64/26'),
            record('retired', '192.0.2.128/25', status: PrefixStatus.retired),
            record('isolated', '192.0.2.128/25', domain: 'separate'),
          ]);
      expect(plan.summary.totalAddresses, BigInt.from(256));
      expect(plan.summary.blockedAddresses, BigInt.from(65));
      expect(plan.summary.freeAddresses, BigInt.from(191));
      expect(plan.summary.totalSlots, BigInt.from(8));
      expect(plan.summary.freeSlots, BigInt.from(5));
      expect(
          plan.summary.blockedIntervals.map(
              (interval) => '${interval.firstAddress}-${interval.lastAddress}'),
          ['192.0.2.1-192.0.2.1', '192.0.2.64-192.0.2.127']);
      expect(
          plan.summary.freeIntervals.map(
              (interval) => '${interval.firstAddress}-${interval.lastAddress}'),
          [
            '192.0.2.0-192.0.2.0',
            '192.0.2.2-192.0.2.63',
            '192.0.2.128-192.0.2.255'
          ]);
      expect(plan.summary.largestFreeBlock?.canonical, '192.0.2.128/25');
      expect(plan.candidates.single.cidr.canonical, '192.0.2.32/27');
      expect(
          jsonDecode(jsonEncode(plan.toJson()))['summary']['freeSlots'], '5');
    });

    test(
        'partial slot occupation can exhaust aligned capacity before raw space',
        () {
      final plan = AddressPlanner.plan(
          parent: Cidr.parse('192.0.2.0/29'),
          routingDomain: 'corporate',
          prefixLength: 30,
          records: [
            record('first', '192.0.2.1/32'),
            record('last', '192.0.2.6/32')
          ]);
      expect(plan.summary.freeAddresses, BigInt.from(6));
      expect(plan.summary.freeSlots, BigInt.zero);
      expect(plan.candidates, isEmpty);
      expect(plan.summary.largestFreeBlock?.canonical, '192.0.2.2/31');
    });

    test('selected ancestry is ignored while unrelated containing ranges block',
        () {
      final pool = record('pool', '10.42.0.0/24',
          kind: PrefixKind.allocation, parentId: 'enterprise');
      final records = [
        record('enterprise', '10.0.0.0/8', kind: PrefixKind.allocation),
        pool,
        record('child', '10.42.0.0/26', parentId: 'pool')
      ];
      final plan = AddressPlanner.plan(
          parent: Cidr.parse(pool.cidr),
          routingDomain: 'corporate',
          parentId: pool.id,
          prefixLength: 26,
          records: records);
      expect(plan.summary.freeSlots, BigInt.from(3));
      expect(plan.candidates.first.cidr.canonical, '10.42.0.64/26');
      final blocked = AddressPlanner.plan(
          parent: Cidr.parse(pool.cidr),
          routingDomain: 'corporate',
          parentId: pool.id,
          prefixLength: 26,
          records: [...records, record('unrelated', '10.42.0.0/16')]);
      expect(blocked.summary.freeSlots, BigInt.zero);
      expect(blocked.summary.freeIntervals, isEmpty);
      expect(blocked.summary.largestFreeBlock, isNull);
    });

    test('huge IPv6 totals and final address remain exact without enumeration',
        () {
      final all = AddressPlanner.plan(
          parent: Cidr.parse('::/0'),
          routingDomain: 'corporate',
          prefixLength: 128,
          limit: 3,
          records: [record('half', '::/1')]);
      expect(all.summary.freeSlots.toString(),
          '170141183460469231731687303715884105728');
      expect(all.summary.totalSlots.toString(),
          '340282366920938463463374607431768211456');
      expect(all.summary.largestFreeBlock?.canonical, '8000::/1');
      expect(all.candidates, hasLength(3));
      expect(all.candidates.first.cidr.canonical, '8000::/128');
      expect(all.candidates[1].cidr.canonical,
          'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128');
      final last = AddressPlanner.plan(
          parent: Cidr.parse('ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe/127'),
          routingDomain: 'corporate',
          prefixLength: 128,
          records: [
            record('first', 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe/128')
          ]);
      expect(last.summary.freeSlots, BigInt.one);
      expect(last.candidates.single.cidr.canonical,
          'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128');
    });

    test(
        'legacy available retains first-address ordering after shared calculation',
        () {
      final parent = Cidr.parse('192.0.2.0/24');
      expect(
          InventoryRules.available(
                  parent: parent,
                  prefixLength: 26,
                  records: [],
                  routingDomain: 'corporate')
              .map((cidr) => cidr.canonical),
          [
            '192.0.2.0/26',
            '192.0.2.64/26',
            '192.0.2.128/26',
            '192.0.2.192/26'
          ]);
      final plan = AddressPlanner.plan(
          parent: parent,
          prefixLength: 26,
          records: [],
          routingDomain: 'corporate');
      expect(plan.candidates.map((item) => item.cidr.canonical), [
        '192.0.2.0/26',
        '192.0.2.192/26',
        '192.0.2.64/26',
        '192.0.2.128/26'
      ]);
    });
  });

  group('recommendations', () {
    test(
        'best fit preserves larger maximal aligned blocks and is deterministic',
        () {
      final parent = Cidr.parse('192.0.2.0/24');
      final records = [
        record('first', '192.0.2.128/26'),
        record('second', '192.0.2.192/27')
      ];
      final plan = AddressPlanner.plan(
          parent: parent,
          routingDomain: 'corporate',
          records: records,
          prefixLength: 27,
          limit: 2);
      expect(plan.summary.freeSlots, BigInt.from(5));
      expect(plan.candidates.map((item) => item.cidr.canonical),
          ['192.0.2.224/27', '192.0.2.0/27']);
      expect(
          AddressPlanner.plan(
                  parent: parent,
                  routingDomain: 'corporate',
                  records: records.reversed.toList(),
                  prefixLength: 27,
                  limit: 2)
              .candidates
              .map((item) => item.cidr.canonical),
          plan.candidates.map((item) => item.cidr.canonical));
      expect(plan.candidates.first.rationale, contains('192.0.2.224/27'));
      expect(plan.candidates.first.rationale, contains('generic'));
      expect(plan.candidates.first.rationale,
          contains('Available in this inventory'));
    });

    test(
        'OCI demand chooses /25 with 124 planned and one spare assignable address',
        () {
      final plan = AddressPlanner.plan(
          parent: Cidr.parse('10.42.0.0/24'),
          routingDomain: 'corporate',
          records: [],
          demand: AddressDemand(
              addresses: BigInt.from(100),
              growthPercent: 20,
              additionalAddresses: BigInt.from(4)),
          policy: AddressPolicy.ociIpv4Subnet);
      expect(plan.targetAddresses, BigInt.from(124));
      expect(plan.prefixLength, 25);
      expect(
          plan.candidates.first.details.assignableAddresses, BigInt.from(125));
      expect(plan.candidates.first.rationale, contains('100'));
      expect(plan.candidates.first.rationale, contains('20%'));
      expect(plan.candidates.first.rationale, contains('4 additional'));
      expect(plan.candidates.first.rationale, contains('124'));
      expect(plan.candidates.first.rationale, contains('1 spare'));
      expect(plan.candidates.first.rationale, contains('/26'));
      expect(plan.candidates.first.rationale, contains('61'));
      expect(plan.warnings.join(' '), contains('inventory'));
    });

    test('demand rejects unsupported policies and no fitting allowed prefix',
        () {
      final demand =
          AddressDemand(addresses: BigInt.from(124), growthPercent: 0);
      AllocationPlan plan(
              {String parent = '10.42.0.0/24',
              AddressPolicy policy = AddressPolicy.ociIpv4Subnet,
              int? prefixLength,
              AddressDemand? supplied}) =>
          AddressPlanner.plan(
              parent: Cidr.parse(parent),
              routingDomain: 'corporate',
              records: [],
              demand: supplied ?? demand,
              policy: policy,
              prefixLength: prefixLength);
      expect(() => plan(parent: '10.42.0.0/26'), throwsArgumentError);
      expect(() => plan(parent: '::/0'), throwsArgumentError);
      expect(() => plan(policy: AddressPolicy.generic), throwsArgumentError);
      expect(() => plan(prefixLength: 25), throwsArgumentError);
      expect(
          () => plan(
              supplied: AddressDemand(
                  addresses: BigInt.from(65534), growthPercent: 0),
              parent: '10.0.0.0/8'),
          throwsArgumentError);
      expect(
          () => AddressPlanner.plan(
              parent: Cidr.parse('10.42.0.0/24'),
              routingDomain: 'corporate',
              records: []),
          throwsArgumentError);
    });

    test(
        'strict planning validates prefix policy, domain, limit, and inventory',
        () {
      AllocationPlan plan(
              {int prefix = 28,
              String domain = 'corporate',
              int limit = 12,
              List<PrefixRecord> records = const [],
              String? parentId,
              AddressPolicy policy = AddressPolicy.generic}) =>
          AddressPlanner.plan(
              parent: Cidr.parse('10.42.0.0/24'),
              routingDomain: domain,
              records: records,
              prefixLength: prefix,
              limit: limit,
              parentId: parentId,
              policy: policy);
      expect(() => plan(prefix: 23), throwsRangeError);
      expect(() => plan(prefix: 33), throwsRangeError);
      expect(() => plan(domain: ' '), throwsArgumentError);
      expect(() => plan(limit: -1), throwsRangeError);
      expect(() => plan(prefix: 31, policy: AddressPolicy.ociIpv4Subnet),
          throwsArgumentError);
      expect(() => plan(records: [record('broken', '10.42.0.1/24')]),
          throwsArgumentError);
      expect(
          () => plan(records: [
                record('bad-parent', '10.42.0.0/24', parentId: 'missing')
              ]),
          throwsArgumentError);
      expect(() => plan(parentId: 'absent'), throwsArgumentError);
      final countOnly = plan(limit: 0);
      expect(countOnly.candidates, isEmpty);
      expect(countOnly.summary.freeSlots, BigInt.from(16));
    });
  });
}
