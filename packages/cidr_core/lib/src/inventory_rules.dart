// CIDR Atlas
// Hierarchy, overlap, and allocation rules.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'cidr.dart';
import 'prefix_record.dart';
import 'inventory_index.dart';
import 'planning_space.dart';

final class Conflict {
  const Conflict({
    required this.first,
    required this.second,
    required this.reason,
  });

  final PrefixRecord first;
  final PrefixRecord second;
  final String reason;
}

/// Shared rules used by the app, imports, CLI, and allocation planning.
abstract final class InventoryRules {
  /// Reports conflicting pairs, preserving both records for review.
  ///
  /// Invalid CIDRs are reported by [validate] and skipped here. Merely being
  /// numerically contained does not establish a legitimate hierarchy.
  static List<Conflict> conflicts(List<PrefixRecord> records) {
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

  /// Structural errors prevent a save. Overlap conflicts remain inspectable
  /// inventory data and therefore are deliberately not returned here.
  static List<String> validate(List<PrefixRecord> records) =>
      validateInventory(records);

  /// Finds the first free aligned subnet blocks without enumerating the
  /// address space. Runtime is bounded by the inventory size and [limit],
  /// including when planning /128s inside an IPv6 /0.
  ///
  /// Supply [parentId] when planning within an inventory record. Only that
  /// selected record and its validated ancestors are ignored. The selected
  /// pool must be a non-retired allocation or VCN, not an existing subnet.
  /// Without [parentId], every overlapping non-retired record blocks space;
  /// numeric containment alone never establishes a legitimate ancestor.
  static List<Cidr> available({
    required Cidr parent,
    required int prefixLength,
    required List<PrefixRecord> records,
    required String routingDomain,
    String? parentId,
    int limit = 8,
  }) {
    if (prefixLength < parent.prefixLength || prefixLength > parent.bitLength) {
      throw RangeError.range(
        prefixLength,
        parent.prefixLength,
        parent.bitLength,
        'prefixLength',
      );
    }
    if (limit < 0) {
      throw RangeError.value(limit, 'limit', 'Must not be negative.');
    }
    if (routingDomain.trim().isEmpty) {
      throw ArgumentError.value(
        routingDomain,
        'routingDomain',
        'Must not be blank.',
      );
    }
    final space = PlanningSpace.calculate(
      parent: parent,
      records: records,
      routingDomain: routingDomain,
      parentId: parentId,
      includeRanges: limit != 0,
    );
    final size = BigInt.one << (parent.bitLength - prefixLength);
    final result = <Cidr>[];
    for (final interval in space.free) {
      var candidate = alignUp(interval.start, size);
      while (result.length < limit &&
          candidate + size - BigInt.one <= interval.end) {
        result.add(
            Cidr.fromNetworkAddress(candidate, prefixLength, parent.version));
        candidate += size;
      }
      if (result.length == limit) break;
    }
    return result;
  }
}
