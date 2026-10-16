// CIDR Atlas
// Conflict sweep equivalence, change-scoped conflicts, and scale tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:math';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_core/src/inventory_index.dart';
import 'package:test/test.dart';

/// The original all-pairs conflict scan, kept as the reference result.
List<Conflict> _allPairsOracle(List<PrefixRecord> records) {
  final index = InventoryIndex(records);
  final result = <Conflict>[];
  for (var i = 0; i < records.length; i++) {
    final first = records[i];
    final firstNetwork = index.networks[first];
    if (first.status == PrefixStatus.retired || firstNetwork == null) {
      continue;
    }
    for (var j = i + 1; j < records.length; j++) {
      final second = records[j];
      final secondNetwork = index.networks[second];
      if (second.status == PrefixStatus.retired ||
          secondNetwork == null ||
          !sameRoutingDomain(first.routingDomain, second.routingDomain) ||
          !firstNetwork.overlaps(secondNetwork)) {
        continue;
      }
      final linked =
          (index.validAncestors(first)?.contains(second.id) ?? false) ||
              (index.validAncestors(second)?.contains(first.id) ?? false);
      if (linked) {
        continue;
      }
      result.add(
        Conflict(
          first: first,
          second: second,
          reason: firstNetwork == secondNetwork
              ? 'Duplicate CIDR ${firstNetwork.canonical} in routing domain ${first.routingDomain}.'
              : '${firstNetwork.canonical} overlaps ${secondNetwork.canonical} without a valid parent or OCI VCN/subnet relationship.',
        ),
      );
    }
  }
  return result;
}

void _expectSameConflicts(
  List<Conflict> actual,
  List<Conflict> expected,
  String context,
) {
  expect(actual, hasLength(expected.length), reason: context);
  for (var i = 0; i < expected.length; i++) {
    expect(
      identical(actual[i].first, expected[i].first),
      isTrue,
      reason: '$context: first of conflict $i',
    );
    expect(
      identical(actual[i].second, expected[i].second),
      isTrue,
      reason: '$context: second of conflict $i',
    );
    expect(actual[i].reason, expected[i].reason, reason: context);
  }
}

/// Fictional inventories with deliberately dense overlaps and relationships.
List<PrefixRecord> _randomInventory(Random random) {
  T pick<T>(List<T> values) => values[random.nextInt(values.length)];
  String ipv4() {
    final prefix = 14 + random.nextInt(13);
    final address = random.nextInt(1 << 18) << 14;
    final aligned = address >> (32 - prefix) << (32 - prefix);
    return Cidr.fromNetworkAddress(BigInt.from(aligned), prefix, 4).canonical;
  }

  String ipv6() {
    final prefix = 44 + random.nextInt(21);
    final address = (BigInt.parse('20010db8', radix: 16) << 96) |
        (BigInt.from(random.nextInt(1 << 20)) << 64);
    final hostBits = 128 - prefix;
    return Cidr.fromNetworkAddress(address >> hostBits << hostBits, prefix, 6)
        .canonical;
  }

  final count = 2 + random.nextInt(39);
  final records = <PrefixRecord>[];
  for (var i = 0; i < count; i++) {
    final roll = random.nextInt(100);
    if (records.isNotEmpty && roll < 4) {
      // The same instance listed twice.
      records.add(pick(records));
      continue;
    }
    final kind = pick(PrefixKind.values);
    final cidr = roll < 8
        ? pick(['malformed', '10.0.0.1/24', '10.0.0.0/08'])
        : roll < 14 && records.isNotEmpty
            ? pick(records).cidr
            : random.nextInt(4) == 0
                ? ipv6()
                : ipv4();
    final id = records.isNotEmpty && random.nextInt(25) == 0
        ? pick(records).id
        : 'record-$i';
    final explicitParent = records.isNotEmpty && random.nextInt(3) == 0;
    records.add(
      PrefixRecord(
        id: id,
        cidr: cidr,
        name: id,
        routingDomain: pick(['corp', 'corp', 'corp ', ' corp', 'lab']),
        kind: kind,
        status: random.nextInt(8) == 0
            ? PrefixStatus.retired
            : pick([PrefixStatus.planned, PrefixStatus.reserved]),
        tenancy: pick(['', 'tenancy-a', 'tenancy-a', 'tenancy-b']),
        region: pick(['', 'region-1', 'region-1', 'region-2']),
        resourceId: kind == PrefixKind.vcn && random.nextBool()
            ? pick(['ocid.vcn.1', 'ocid.vcn.2', 'ocid.vcn.3'])
            : '',
        vcnId: kind == PrefixKind.subnet && random.nextInt(4) != 0
            ? pick(['ocid.vcn.1', 'ocid.vcn.2', 'ocid.vcn.3', 'ocid.vcn.9'])
            : '',
        parentId: explicitParent
            ? (random.nextInt(10) == 0 ? 'missing' : pick(records).id)
            : '',
      ),
    );
  }
  // Give some records valid, nested children so legitimate links occur.
  for (var i = 0; i < 4 && records.isNotEmpty; i++) {
    final parent = pick(records);
    final network = _tryParse(parent.cidr);
    if (network == null || network.prefixLength >= network.bitLength - 2) {
      continue;
    }
    final childPrefix = network.prefixLength + 1 + random.nextInt(2);
    final child = Cidr.fromNetworkAddress(
      network.networkAddress,
      childPrefix,
      network.version,
    );
    final ociInferred = parent.kind == PrefixKind.vcn &&
        parent.resourceId.isNotEmpty &&
        random.nextBool();
    records.add(
      PrefixRecord(
        id: 'child-$i',
        cidr: child.canonical,
        name: 'child-$i',
        routingDomain: parent.routingDomain,
        kind: parent.kind == PrefixKind.allocation
            ? pick([PrefixKind.allocation, PrefixKind.vcn])
            : PrefixKind.subnet,
        tenancy: parent.tenancy,
        region: parent.region,
        vcnId: parent.kind == PrefixKind.vcn ? parent.resourceId : '',
        parentId: ociInferred ? '' : parent.id,
      ),
    );
  }
  records.shuffle(random);
  return records;
}

Cidr? _tryParse(String value) {
  try {
    return Cidr.parse(value);
  } on FormatException {
    return null;
  }
}

void main() {
  test('sorted sweep reproduces the all-pairs result, orientation, and order',
      () {
    final random = Random(20261016);
    var conflicting = 0;
    for (var round = 0; round < 1500; round++) {
      final records = _randomInventory(random);
      final expected = _allPairsOracle(records);
      if (expected.isNotEmpty) conflicting++;
      _expectSameConflicts(
        InventoryRules.conflicts(records),
        expected,
        'round $round',
      );
    }
    // The generator must exercise both outcomes to be meaningful.
    expect(conflicting, greaterThan(500));
    expect(conflicting, lessThan(1500));
  });

  test('conflictsFor returns exactly the conflicts involving changed ids', () {
    final random = Random(42);
    for (var round = 0; round < 800; round++) {
      final records = _randomInventory(random);
      final ids = records.map((record) => record.id).toSet().toList();
      final changed = {
        for (final id in ids)
          if (random.nextInt(4) == 0) id,
        if (random.nextInt(5) == 0) 'not-in-inventory',
      };
      final expected = _allPairsOracle(records)
          .where((conflict) =>
              changed.contains(conflict.first.id) ||
              changed.contains(conflict.second.id))
          .toList();
      _expectSameConflicts(
        InventoryRules.conflictsFor(changed, records),
        expected,
        'round $round',
      );
    }
    expect(InventoryRules.conflictsFor({}, _randomInventory(random)), isEmpty);
  });

  test('a subnet in the second block of a multi-CIDR VCN inherits ancestry',
      () {
    PrefixRecord vcn(String id, String cidr) => PrefixRecord(
          id: id,
          cidr: cidr,
          name: id,
          routingDomain: 'corp',
          resourceId: 'ocid.vcn.multi',
          parentId: 'allocation',
        );
    final records = [
      const PrefixRecord(
        id: 'allocation',
        cidr: '10.40.0.0/15',
        name: 'allocation',
        routingDomain: 'corp',
        kind: PrefixKind.allocation,
      ),
      vcn('vcn-block-1', '10.40.0.0/16'),
      vcn('vcn-block-2', '10.41.0.0/16'),
      const PrefixRecord(
        id: 'subnet',
        cidr: '10.41.1.0/24',
        name: 'subnet',
        routingDomain: 'corp',
        kind: PrefixKind.subnet,
        vcnId: 'ocid.vcn.multi',
      ),
    ];
    expect(InventoryRules.validate(records), isEmpty);
    expect(InventoryRules.conflicts(records), isEmpty);
    expect(
      InventoryIndex(records).validAncestors(records.last),
      {'vcn-block-2', 'allocation'},
    );
  });

  group('scale', () {
    test('10k disjoint records are checked within a generous time budget', () {
      final records = [
        for (var i = 0; i < 10000; i++)
          PrefixRecord(
            id: 'vcn-$i',
            cidr: '10.${i ~/ 256}.${i % 256}.0/24',
            name: 'vcn-$i',
            routingDomain: 'corp',
          ),
      ];
      final watch = Stopwatch()..start();
      final conflicts = InventoryRules.conflicts(records);
      final scoped = InventoryRules.conflictsFor({'vcn-5000'}, records);
      watch.stop();
      expect(conflicts, isEmpty);
      expect(scoped, isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });

    test('10k-record OCI hierarchy without conflicts is checked quickly', () {
      final records = <PrefixRecord>[
        const PrefixRecord(
          id: 'allocation',
          cidr: '10.0.0.0/8',
          name: 'allocation',
          routingDomain: 'corp',
          kind: PrefixKind.allocation,
        ),
      ];
      for (var v = 0; v < 1111; v++) {
        final third = v % 256;
        final second = v ~/ 256;
        records.add(PrefixRecord(
          id: 'vcn-$v',
          cidr: '10.$second.$third.0/24',
          name: 'vcn-$v',
          routingDomain: 'corp',
          resourceId: 'ocid.vcn.$v',
          parentId: 'allocation',
        ));
        for (var s = 0; s < 8; s++) {
          records.add(PrefixRecord(
            id: 'subnet-$v-$s',
            cidr: '10.$second.$third.${s * 16}/28',
            name: 'subnet-$v-$s',
            routingDomain: 'corp',
            kind: PrefixKind.subnet,
            vcnId: 'ocid.vcn.$v',
          ));
        }
      }
      expect(records.length, greaterThanOrEqualTo(10000));
      final watch = Stopwatch()..start();
      final conflicts = InventoryRules.conflicts(records);
      watch.stop();
      expect(conflicts, isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(5000));
      final reserved = [
        ...records,
        const PrefixRecord(
          id: 'candidate',
          cidr: '10.0.0.0/28',
          name: 'candidate',
          routingDomain: 'corp',
          kind: PrefixKind.subnet,
        ),
      ];
      final scoped = Stopwatch()..start();
      final found = InventoryRules.conflictsFor({'candidate'}, reserved);
      scoped.stop();
      expect(found.map((conflict) => conflict.second.id).toSet(), {
        'candidate',
      });
      expect(
        found.map((conflict) => conflict.first.id).toSet(),
        {'allocation', 'vcn-0', 'subnet-0-0'},
      );
      expect(scoped.elapsedMilliseconds, lessThan(5000));
    });
  });
}
