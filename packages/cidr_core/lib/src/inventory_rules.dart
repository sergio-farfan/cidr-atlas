import 'cidr.dart';
import 'prefix_record.dart';

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
    final index = _InventoryIndex(records);
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
            !_sameDomain(first.routingDomain, second.routingDomain) ||
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
  static List<String> validate(List<PrefixRecord> records) {
    final index = _InventoryIndex(records);
    final errors = <String>[];
    for (final id in index.duplicates) {
      errors.add('Duplicate record id "$id".');
    }
    for (final record in records) {
      final label = record.id.isEmpty ? '(unnamed record)' : record.id;
      if (record.id.trim().isEmpty) errors.add('$label: id is required.');
      if (record.name.trim().isEmpty) errors.add('$label: name is required.');
      if (record.routingDomain.trim().isEmpty) {
        errors.add('$label: routing domain is required.');
      }
      if (!index.networks.containsKey(record)) {
        try {
          Cidr.parse(record.cidr);
        } on FormatException catch (error) {
          errors.add('$label: ${error.message}');
        }
      }
      if (record.parentId.isEmpty) continue;
      final parent = index.byId[record.parentId];
      if (index.duplicates.contains(record.parentId)) {
        errors.add(
          '$label: parent "${record.parentId}" is ambiguous because its id is duplicated.',
        );
      } else if (parent == null) {
        errors.add('$label: parent "${record.parentId}" does not exist.');
      } else {
        final problem = index.parentProblem(record, parent);
        if (problem != null) errors.add('$label: $problem');
      }
    }

    final completed = <String>{};
    for (final record in records) {
      if (completed.contains(record.id)) continue;
      final path = <String>[];
      final positions = <String, int>{};
      var id = record.id;
      while (id.isNotEmpty && !completed.contains(id)) {
        if (positions.containsKey(id)) {
          final cycle = [...path.skip(positions[id]!), id];
          errors.add('Parent cycle: ${cycle.join(' → ')}.');
          break;
        }
        final current = index.byId[id];
        if (current == null) break;
        positions[id] = path.length;
        path.add(id);
        id = current.parentId;
      }
      completed.addAll(path);
    }
    return errors;
  }

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
    final ignoredIds = <String>{};
    if (parentId != null) {
      final errors = validate(records);
      if (errors.isNotEmpty) {
        throw ArgumentError(
            'Cannot plan from invalid inventory: ${errors.join(' ')}');
      }
      final index = _InventoryIndex(records);
      final selected = index.byId[parentId];
      if (selected == null) {
        throw ArgumentError.value(
            parentId, 'parentId', 'Selected parent does not exist.');
      }
      if (index.networks[selected] != parent ||
          !_sameDomain(selected.routingDomain, routingDomain)) {
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
    if (limit == 0) return [];
    final blocked = <_Interval>[];
    for (final record in records) {
      if (record.status == PrefixStatus.retired ||
          ignoredIds.contains(record.id) ||
          !_sameDomain(record.routingDomain, routingDomain)) {
        continue;
      }
      final network = Cidr.parse(record.cidr);
      if (!parent.overlaps(network)) continue;
      blocked.add(
        _Interval(
          network.networkAddress < parent.networkAddress
              ? parent.networkAddress
              : network.networkAddress,
          network.lastAddress > parent.lastAddress
              ? parent.lastAddress
              : network.lastAddress,
        ),
      );
    }
    blocked.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_Interval>[];
    for (final interval in blocked) {
      if (merged.isEmpty || interval.start > merged.last.end + BigInt.one) {
        merged.add(interval);
      } else if (interval.end > merged.last.end) {
        merged[merged.length - 1] = _Interval(merged.last.start, interval.end);
      }
    }

    final size = BigInt.one << (parent.bitLength - prefixLength);
    final result = <Cidr>[];
    void takeGap(BigInt start, BigInt end) {
      var candidate = ((start + size - BigInt.one) ~/ size) * size;
      while (result.length < limit && candidate + size - BigInt.one <= end) {
        result.add(
          Cidr.fromNetworkAddress(candidate, prefixLength, parent.version),
        );
        candidate += size;
      }
    }

    var cursor = parent.networkAddress;
    for (final interval in merged) {
      takeGap(cursor, interval.start - BigInt.one);
      if (result.length == limit) return result;
      cursor = interval.end + BigInt.one;
    }
    takeGap(cursor, parent.lastAddress);
    return result;
  }

  static bool _validOciRelationship(
    PrefixRecord vcn,
    PrefixRecord subnet,
    Cidr vcnNetwork,
    Cidr subnetNetwork,
  ) =>
      vcn.kind == PrefixKind.vcn &&
      subnet.kind == PrefixKind.subnet &&
      vcn.resourceId.isNotEmpty &&
      vcn.resourceId == subnet.vcnId &&
      _sameDomain(vcn.routingDomain, subnet.routingDomain) &&
      vcn.tenancy == subnet.tenancy &&
      vcn.region == subnet.region &&
      vcnNetwork.contains(subnetNetwork);

  static bool _sameDomain(String first, String second) =>
      first.trim() == second.trim();
}

final class _InventoryIndex {
  _InventoryIndex(List<PrefixRecord> records) {
    for (final record in records) {
      if (byId.containsKey(record.id) || duplicates.contains(record.id)) {
        duplicates.add(record.id);
        byId.remove(record.id);
      } else {
        byId[record.id] = record;
      }
      try {
        networks[record] = Cidr.parse(record.cidr);
      } on FormatException {
        // [InventoryRules.validate] returns the actual parse error.
      }
    }
  }

  final byId = <String, PrefixRecord>{};
  final duplicates = <String>{};
  final networks = <PrefixRecord, Cidr>{};
  final _ancestorCache = <String, Set<String>?>{};

  /// Explicit parent links take precedence. Otherwise a subnet may inherit
  /// its OCI VCN's complete, valid allocation ancestry.
  Set<String>? validAncestors(PrefixRecord record) {
    if (!identical(byId[record.id], record)) return null;
    if (_ancestorCache.containsKey(record.id)) return _ancestorCache[record.id];
    final explicit = _explicitAncestors(record);
    if (explicit == null ||
        record.parentId.isNotEmpty ||
        record.kind != PrefixKind.subnet) {
      _ancestorCache[record.id] = explicit;
      return explicit;
    }
    final subnetNetwork = networks[record];
    if (subnetNetwork == null) return null;
    for (final vcn in byId.values) {
      final vcnNetwork = networks[vcn];
      if (vcnNetwork == null ||
          !InventoryRules._validOciRelationship(
              vcn, record, vcnNetwork, subnetNetwork)) {
        continue;
      }
      final vcnAncestors = _explicitAncestors(vcn);
      if (vcnAncestors == null) continue;
      explicit.add(vcn.id);
      explicit.addAll(vcnAncestors);
    }
    _ancestorCache[record.id] = explicit;
    return explicit;
  }

  Set<String>? _explicitAncestors(PrefixRecord record) {
    final result = <String>{};
    final visited = <String>{record.id};
    var child = record;
    while (child.parentId.isNotEmpty) {
      final parent = byId[child.parentId];
      if (parent == null ||
          !visited.add(parent.id) ||
          parentProblem(child, parent) != null) {
        return null;
      }
      result.add(parent.id);
      child = parent;
    }
    return result;
  }

  String? parentProblem(PrefixRecord child, PrefixRecord parent) {
    if (child.id == parent.id) return 'a record cannot be its own parent.';
    if (!InventoryRules._sameDomain(
      child.routingDomain,
      parent.routingDomain,
    )) {
      return 'parent and child must use the same routing domain.';
    }
    if (parent.kind == PrefixKind.subnet ||
        (parent.kind == PrefixKind.vcn && child.kind != PrefixKind.subnet)) {
      return '${parent.kind.name} cannot be a parent of ${child.kind.name}.';
    }
    final childNetwork = networks[child];
    final parentNetwork = networks[parent];
    if (childNetwork == null || parentNetwork == null) {
      return 'parent and child must both have valid CIDRs.';
    }
    if (!parentNetwork.contains(childNetwork)) {
      return 'CIDR ${child.cidr} is not contained by parent ${parent.cidr}.';
    }
    if (parent.kind == child.kind && parentNetwork == childNetwork) {
      return 'parent and child of the same kind must use different, nested CIDRs.';
    }
    if (parent.kind == PrefixKind.vcn) {
      if (parent.resourceId.isNotEmpty &&
          child.vcnId.isNotEmpty &&
          parent.resourceId != child.vcnId) {
        return 'subnet vcnId does not match its parent VCN resourceId.';
      }
      if (parent.tenancy.isNotEmpty &&
          child.tenancy.isNotEmpty &&
          parent.tenancy != child.tenancy) {
        return 'VCN and subnet parent links cannot cross tenancies.';
      }
      if (parent.region.isNotEmpty &&
          child.region.isNotEmpty &&
          parent.region != child.region) {
        return 'VCN and subnet parent links cannot cross regions.';
      }
    }
    return null;
  }
}

final class _Interval {
  const _Interval(this.start, this.end);
  final BigInt start;
  final BigInt end;
}
