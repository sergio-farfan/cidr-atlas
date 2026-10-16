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
  ///
  /// Pairs are ordered by the position of [Conflict.first] in [records], then
  /// by the position of [Conflict.second], and [Conflict.first] always comes
  /// earlier in [records]. Runtime grows with the inventory size times its
  /// logarithm plus the number of overlapping pairs, not with every pair.
  static List<Conflict> conflicts(List<PrefixRecord> records) =>
      _sweep(records, null);

  /// The subset of [conflicts] in which [Conflict.first] or [Conflict.second]
  /// has an id in [changedIds], in the same order and orientation.
  ///
  /// Use this to check a few edited or reserved records against a large
  /// inventory: routing domains without a changed record are not examined,
  /// and ancestry is evaluated only for overlapping pairs involving a change.
  static List<Conflict> conflictsFor(
    Set<String> changedIds,
    List<PrefixRecord> records,
  ) {
    if (changedIds.isEmpty) return [];
    final changed = List<bool>.generate(
      records.length,
      (i) => changedIds.contains(records[i].id),
      growable: false,
    );
    if (!changed.contains(true)) return [];
    return _sweep(records, changed);
  }

  static List<Conflict> _sweep(
      List<PrefixRecord> records, List<bool>? changed) {
    final index = InventoryIndex(records);
    final buckets = <(String, int), List<_Entry>>{};
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final network = index.networks[record];
      if (record.status == PrefixStatus.retired || network == null) continue;
      (buckets[(record.routingDomain.trim(), network.version)] ??= [])
          .add(_Entry(i, network));
    }
    final pairs = <(int, int)>[];
    for (final bucket in buckets.values) {
      if (changed != null && !bucket.any((entry) => changed[entry.index])) {
        continue;
      }
      bucket.sort((a, b) {
        final start = a.network.networkAddress.compareTo(
          b.network.networkAddress,
        );
        return start != 0 ? start : a.index.compareTo(b.index);
      });
      final active = <_Entry>[];
      for (final current in bucket) {
        final start = current.network.networkAddress;
        active.removeWhere((entry) => entry.network.lastAddress < start);
        // Every remaining active entry starts no later than [current] and
        // ends at or after its start, so the two ranges overlap.
        for (final other in active) {
          if (changed != null &&
              !changed[other.index] &&
              !changed[current.index]) {
            continue;
          }
          final first = other.index < current.index ? other : current;
          final second = identical(first, other) ? current : other;
          final firstRecord = records[first.index];
          final secondRecord = records[second.index];
          final linked = (index
                      .validAncestors(firstRecord)
                      ?.contains(secondRecord.id) ??
                  false) ||
              (index.validAncestors(secondRecord)?.contains(firstRecord.id) ??
                  false);
          if (!linked) pairs.add((first.index, second.index));
        }
        active.add(current);
      }
    }
    pairs.sort((a, b) {
      final first = a.$1.compareTo(b.$1);
      return first != 0 ? first : a.$2.compareTo(b.$2);
    });
    return [
      for (final (i, j) in pairs)
        _conflict(
          records[i],
          records[j],
          index.networks[records[i]]!,
          index.networks[records[j]]!,
        ),
    ];
  }

  static Conflict _conflict(
    PrefixRecord first,
    PrefixRecord second,
    Cidr firstNetwork,
    Cidr secondNetwork,
  ) =>
      Conflict(
        first: first,
        second: second,
        reason: firstNetwork == secondNetwork
            ? 'Duplicate CIDR ${firstNetwork.canonical} in routing domain ${first.routingDomain}.'
            : '${firstNetwork.canonical} overlaps ${secondNetwork.canonical} without a valid parent or OCI VCN/subnet relationship.',
      );

  /// Structural errors prevent a save. Overlap conflicts remain inspectable
  /// inventory data and therefore are deliberately not returned here.
  static List<String> validate(List<PrefixRecord> records) =>
      validateInventory(records);

  /// Human-readable review notices that, unlike [validate], never prevent a
  /// save, reservation or import.
  ///
  /// A subnet whose explicit parent is a placeholder VCN without a resource id
  /// is reported when its `vcnId` names a comparable VCN recorded elsewhere in
  /// the inventory: not retired, in the same routing domain, and in the same
  /// tenancy and region wherever both records set them. The notice names the
  /// subnet, the recorded VCN by name, CIDR and resource id, and the
  /// placeholder parent, and asks to clear or change the parent. The link
  /// itself remains a valid hierarchy, as it was before the VCN was recorded.
  ///
  /// With [involving], only notices that concern a record with one of those
  /// ids (the subnet, its parent, or the recorded VCN) are returned.
  static List<String> advisories(
    List<PrefixRecord> records, {
    Set<String>? involving,
  }) =>
      inventoryAdvisories(records, involving: involving);

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

final class _Entry {
  const _Entry(this.index, this.network);

  final int index;
  final Cidr network;
}
