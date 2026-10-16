// CIDR Atlas
// Internal inventory validation and explicit relationship index.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'cidr.dart';
import 'prefix_record.dart';

List<String> validateInventory(List<PrefixRecord> records) {
  final index = InventoryIndex(records);
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

bool validOciRelationship(
  PrefixRecord vcn,
  PrefixRecord subnet,
  Cidr vcnNetwork,
  Cidr subnetNetwork,
) =>
    vcn.kind == PrefixKind.vcn &&
    subnet.kind == PrefixKind.subnet &&
    vcn.resourceId.isNotEmpty &&
    vcn.resourceId == subnet.vcnId &&
    sameRoutingDomain(vcn.routingDomain, subnet.routingDomain) &&
    vcn.tenancy == subnet.tenancy &&
    vcn.region == subnet.region &&
    vcnNetwork.contains(subnetNetwork);

bool sameRoutingDomain(String first, String second) =>
    first.trim() == second.trim();

final class InventoryIndex {
  InventoryIndex(List<PrefixRecord> records) {
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
          !validOciRelationship(vcn, record, vcnNetwork, subnetNetwork)) {
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
    if (!sameRoutingDomain(
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
