// CIDR Atlas
// Internal shared blocker unions and aligned free-space calculations.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'cidr.dart';
import 'inventory_index.dart';
import 'prefix_record.dart';

final class PlanningRange {
  const PlanningRange(this.start, this.end);

  final BigInt start;
  final BigInt end;
  BigInt get addressCount => end - start + BigInt.one;
}

/// Shared by recommendations and the legacy first-address planner.
final class PlanningSpace {
  PlanningSpace._(this.blocked, this.free);

  factory PlanningSpace.calculate({
    required Cidr parent,
    required List<PrefixRecord> records,
    required String routingDomain,
    String? parentId,
    bool includeRanges = true,
  }) {
    if (routingDomain.trim().isEmpty) {
      throw ArgumentError.value(
          routingDomain, 'routingDomain', 'Must not be blank.');
    }
    final ignoredIds = <String>{};
    if (parentId != null) {
      final errors = validateInventory(records);
      if (errors.isNotEmpty) {
        throw ArgumentError(
            'Cannot plan from invalid inventory: ${errors.join(' ')}');
      }
      final index = InventoryIndex(records);
      final selected = index.byId[parentId];
      if (selected == null) {
        throw ArgumentError.value(
            parentId, 'parentId', 'Selected parent does not exist.');
      }
      if (index.networks[selected] != parent ||
          !sameRoutingDomain(selected.routingDomain, routingDomain)) {
        throw ArgumentError.value(parentId, 'parentId',
            'Selected parent must match the requested CIDR and routing domain.');
      }
      if (selected.kind == PrefixKind.subnet ||
          selected.status == PrefixStatus.retired) {
        throw ArgumentError.value(parentId, 'parentId',
            'Selected pool must be a non-retired allocation or VCN.');
      }
      ignoredIds.add(selected.id);
      ignoredIds.addAll(index.validAncestors(selected)!);
    }
    if (!includeRanges) {
      return PlanningSpace._(const [], const []);
    }
    final ranges = <PlanningRange>[];
    for (final record in records) {
      if (record.status == PrefixStatus.retired ||
          ignoredIds.contains(record.id) ||
          !sameRoutingDomain(record.routingDomain, routingDomain)) {
        continue;
      }
      final network = Cidr.parse(record.cidr);
      if (!parent.overlaps(network)) continue;
      ranges.add(PlanningRange(
        network.networkAddress < parent.networkAddress
            ? parent.networkAddress
            : network.networkAddress,
        network.lastAddress > parent.lastAddress
            ? parent.lastAddress
            : network.lastAddress,
      ));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    final blocked = <PlanningRange>[];
    for (final range in ranges) {
      if (blocked.isEmpty || range.start > blocked.last.end + BigInt.one) {
        blocked.add(range);
      } else if (range.end > blocked.last.end) {
        blocked[blocked.length - 1] =
            PlanningRange(blocked.last.start, range.end);
      }
    }
    final free = <PlanningRange>[];
    var cursor = parent.networkAddress;
    for (final range in blocked) {
      if (cursor < range.start) {
        free.add(PlanningRange(cursor, range.start - BigInt.one));
      }
      cursor = range.end + BigInt.one;
    }
    if (cursor <= parent.lastAddress) {
      free.add(PlanningRange(cursor, parent.lastAddress));
    }
    return PlanningSpace._(List.unmodifiable(blocked), List.unmodifiable(free));
  }

  final List<PlanningRange> blocked;
  final List<PlanningRange> free;
}

BigInt alignUp(BigInt value, BigInt size) =>
    ((value + size - BigInt.one) ~/ size) * size;

/// At most twice the address width CIDRs per interval, regardless of capacity.
List<Cidr> maximalAlignedBlocks(PlanningRange range, int version) {
  final width = version == 4 ? 32 : 128;
  final blocks = <Cidr>[];
  var cursor = range.start;
  while (cursor <= range.end) {
    final remainingBits = (range.end - cursor + BigInt.one).bitLength - 1;
    final alignmentBits =
        cursor == BigInt.zero ? width : (cursor & -cursor).bitLength - 1;
    final hostBits =
        remainingBits < alignmentBits ? remainingBits : alignmentBits;
    blocks.add(Cidr.fromNetworkAddress(cursor, width - hostBits, version));
    cursor += BigInt.one << hostBits;
  }
  return blocks;
}
