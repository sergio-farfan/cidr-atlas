// CIDR Atlas
// Exact address capacity and explainable allocation planning.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'cidr.dart';
import 'inventory_index.dart';
import 'planning_space.dart';
import 'prefix_record.dart';

enum AddressPolicy { generic, ociIpv4Subnet }

enum DemandBasis { current, peak }

/// Explicit planning demand, without hidden growth or per-resource IP estimates.
final class AddressDemand {
  AddressDemand({
    required this.addresses,
    required this.growthPercent,
    BigInt? additionalAddresses,
    this.basis = DemandBasis.current,
  }) : additionalAddresses = additionalAddresses ?? BigInt.zero {
    if (addresses <= BigInt.zero) {
      throw ArgumentError.value(addresses, 'addresses', 'Must be positive.');
    }
    if (growthPercent < 0) {
      throw ArgumentError.value(
          growthPercent, 'growthPercent', 'Must not be negative.');
    }
    if (this.additionalAddresses.isNegative) {
      throw ArgumentError.value(
          additionalAddresses, 'additionalAddresses', 'Must not be negative.');
    }
  }

  final BigInt addresses;
  final int growthPercent;
  final BigInt additionalAddresses;
  final DemandBasis basis;

  BigInt get targetAddresses =>
      (addresses * (BigInt.from(100) + BigInt.from(growthPercent)) +
              BigInt.from(99)) ~/
          BigInt.from(100) +
      additionalAddresses;
}

/// Mathematical CIDR details and separately identified provider capacity.
final class CidrDetails {
  CidrDetails.from(this.cidr, {this.policy = AddressPolicy.generic});

  final Cidr cidr;
  final AddressPolicy policy;

  int get hostBits => cidr.bitLength - cidr.prefixLength;
  BigInt get totalAddresses => cidr.addressCount;
  String get firstAddress => _formatAddress(cidr.networkAddress, cidr.version);
  String get lastAddress => _formatAddress(cidr.lastAddress, cidr.version);

  String? get subnetMask => cidr.version == 4
      ? _formatAddress(
          ((BigInt.one << 32) - BigInt.one) ^
              ((BigInt.one << hostBits) - BigInt.one),
          4,
        )
      : null;

  bool get _eligibleOci =>
      policy == AddressPolicy.ociIpv4Subnet &&
      cidr.version == 4 &&
      cidr.prefixLength >= 16 &&
      cidr.prefixLength <= 30;

  BigInt? get assignableAddresses =>
      _eligibleOci ? totalAddresses - BigInt.from(3) : null;
  String? get assignableFirst =>
      _eligibleOci ? _formatAddress(cidr.networkAddress + BigInt.two, 4) : null;
  String? get assignableLast =>
      _eligibleOci ? _formatAddress(cidr.lastAddress - BigInt.one, 4) : null;

  String get policyNote {
    if (policy == AddressPolicy.generic) {
      return 'Exact mathematical capacity; provider assignable capacity is not '
          'assumed. IPv6 has no broadcast-address subtraction.';
    }
    if (cidr.version == 6) {
      return 'OCI IPv4 subnet policy does not apply to IPv6. Exact total capacity '
          'is shown; OCI IPv6 assignable capacity remains unresolved.';
    }
    if (!_eligibleOci) {
      return 'Ineligible OCI IPv4 subnet prefix. OCI IPv4 subnets require /16 '
          'through /30; raw capacity remains available for generic planning.';
    }
    return 'OCI IPv4 subnet capacity reserves the first two addresses and the '
        'final address (three total). This subnet policy is not VCN capacity '
        'or a service-quota guarantee.';
  }

  Cidr containingSupernet(int prefixLength) {
    if (prefixLength < 0 || prefixLength > cidr.prefixLength) {
      throw RangeError.range(
          prefixLength, 0, cidr.prefixLength, 'prefixLength');
    }
    final hostBits = cidr.bitLength - prefixLength;
    return Cidr.fromNetworkAddress(
        (cidr.networkAddress >> hostBits) << hostBits,
        prefixLength,
        cidr.version);
  }

  Map<String, dynamic> toJson() => {
        'cidr': cidr.canonical,
        'version': cidr.version,
        'prefixLength': cidr.prefixLength,
        'hostBits': hostBits,
        'totalAddresses': totalAddresses.toString(),
        'firstAddress': firstAddress,
        'lastAddress': lastAddress,
        'subnetMask': subnetMask,
        'policy': policy.name,
        'assignableAddresses': assignableAddresses?.toString(),
        'assignableFirst': assignableFirst,
        'assignableLast': assignableLast,
        'policyNote': policyNote,
      };
}

/// Inclusive address range. No assumption of CIDR alignment is made.
final class AddressInterval {
  AddressInterval(
      {required this.start, required this.end, required this.version}) {
    if (version != 4 && version != 6) {
      throw ArgumentError.value(version, 'version', 'Must be 4 or 6.');
    }
    if (start.isNegative ||
        end < start ||
        end >= (BigInt.one << (version == 4 ? 32 : 128))) {
      throw ArgumentError(
          'Interval must have ordered bounds inside the IPv$version address space.');
    }
  }

  final BigInt start;
  final BigInt end;
  final int version;
  BigInt get addressCount => end - start + BigInt.one;
  String get firstAddress => _formatAddress(start, version);
  String get lastAddress => _formatAddress(end, version);

  Map<String, dynamic> toJson() => {
        'start': start.toString(),
        'end': end.toString(),
        'version': version,
        'addressCount': addressCount.toString(),
        'firstAddress': firstAddress,
        'lastAddress': lastAddress,
      };
}

final class AddressSpaceSummary {
  AddressSpaceSummary({
    required this.parent,
    required List<AddressInterval> freeIntervals,
    required List<AddressInterval> blockedIntervals,
    required this.totalAddresses,
    required this.freeAddresses,
    required this.blockedAddresses,
    required this.totalSlots,
    required this.freeSlots,
    required this.largestFreeBlock,
  })  : freeIntervals = List.unmodifiable(freeIntervals),
        blockedIntervals = List.unmodifiable(blockedIntervals);

  final Cidr parent;
  final List<AddressInterval> freeIntervals;
  final List<AddressInterval> blockedIntervals;
  final BigInt totalAddresses;
  final BigInt freeAddresses;
  final BigInt blockedAddresses;
  final BigInt totalSlots;
  final BigInt freeSlots;
  final Cidr? largestFreeBlock;

  Map<String, dynamic> toJson() => {
        'parent': parent.canonical,
        'freeIntervals':
            freeIntervals.map((interval) => interval.toJson()).toList(),
        'blockedIntervals':
            blockedIntervals.map((interval) => interval.toJson()).toList(),
        'totalAddresses': totalAddresses.toString(),
        'freeAddresses': freeAddresses.toString(),
        'blockedAddresses': blockedAddresses.toString(),
        'totalSlots': totalSlots.toString(),
        'freeSlots': freeSlots.toString(),
        'largestFreeBlock': largestFreeBlock?.canonical,
      };
}

final class AllocationRecommendation {
  const AllocationRecommendation(
      {required this.cidr, required this.details, required this.rationale});

  final Cidr cidr;
  final CidrDetails details;
  final String rationale;

  Map<String, dynamic> toJson() => {
        'cidr': cidr.canonical,
        'details': details.toJson(),
        'rationale': rationale,
      };
}

final class AllocationPlan {
  AllocationPlan({
    required this.summary,
    required this.prefixLength,
    required this.targetAddresses,
    required List<AllocationRecommendation> candidates,
    required List<String> warnings,
  })  : candidates = List.unmodifiable(candidates),
        warnings = List.unmodifiable(warnings);

  final AddressSpaceSummary summary;
  final int prefixLength;
  final BigInt? targetAddresses;
  final List<AllocationRecommendation> candidates;
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'summary': summary.toJson(),
        'prefixLength': prefixLength,
        'targetAddresses': targetAddresses?.toString(),
        'candidates':
            candidates.map((candidate) => candidate.toJson()).toList(),
        'warnings': warnings,
      };
}

/// Calculates availability against all supplied records in one routing domain.
/// The candidate limit never limits the exact interval or slot totals.
abstract final class AddressPlanner {
  static AllocationPlan plan({
    required Cidr parent,
    required String routingDomain,
    required List<PrefixRecord> records,
    String? parentId,
    int? prefixLength,
    AddressDemand? demand,
    AddressPolicy policy = AddressPolicy.generic,
    int limit = 12,
  }) {
    if ((prefixLength == null) == (demand == null)) {
      throw ArgumentError('Supply exactly one of prefixLength or demand.');
    }
    if (limit < 0) {
      throw RangeError.value(limit, 'limit', 'Must not be negative.');
    }
    if (routingDomain.trim().isEmpty) {
      throw ArgumentError.value(
          routingDomain, 'routingDomain', 'Must not be blank.');
    }
    final errors = validateInventory(records);
    if (errors.isNotEmpty) {
      throw ArgumentError(
          'Cannot plan from invalid inventory: ${errors.join(' ')}');
    }
    final selectedPrefix =
        prefixLength ?? _demandPrefix(parent, demand!, policy);
    if (selectedPrefix < parent.prefixLength ||
        selectedPrefix > parent.bitLength) {
      throw RangeError.range(selectedPrefix, parent.prefixLength,
          parent.bitLength, 'prefixLength');
    }
    if (policy == AddressPolicy.ociIpv4Subnet &&
        (parent.version != 4 || selectedPrefix < 16 || selectedPrefix > 30)) {
      throw ArgumentError(
          'OCI IPv4 subnet recommendations require IPv4 prefixes /16 through /30.');
    }
    final space = PlanningSpace.calculate(
        parent: parent,
        records: records,
        routingDomain: routingDomain,
        parentId: parentId);
    final size = BigInt.one << (parent.bitLength - selectedPrefix);
    var freeAddresses = BigInt.zero;
    var freeSlots = BigInt.zero;
    final blocks = <Cidr>[];
    for (final range in space.free) {
      freeAddresses += range.addressCount;
      final start = alignUp(range.start, size);
      if (start + size - BigInt.one <= range.end) {
        freeSlots += (range.end - start + BigInt.one) ~/ size;
      }
      blocks.addAll(maximalAlignedBlocks(range, parent.version));
    }
    Cidr? largest;
    for (final block in blocks) {
      if (largest == null ||
          block.addressCount > largest.addressCount ||
          (block.addressCount == largest.addressCount &&
              block.networkAddress < largest.networkAddress)) {
        largest = block;
      }
    }
    AddressInterval interval(PlanningRange range) => AddressInterval(
        start: range.start, end: range.end, version: parent.version);
    final summary = AddressSpaceSummary(
      parent: parent,
      freeIntervals: space.free.map(interval).toList(),
      blockedIntervals: space.blocked.map(interval).toList(),
      totalAddresses: parent.addressCount,
      freeAddresses: freeAddresses,
      blockedAddresses: parent.addressCount - freeAddresses,
      totalSlots: BigInt.one << (selectedPrefix - parent.prefixLength),
      freeSlots: freeSlots,
      largestFreeBlock: largest,
    );
    final fitting =
        blocks.where((block) => block.prefixLength <= selectedPrefix).toList()
          ..sort((a, b) {
            final capacity = b.prefixLength.compareTo(a.prefixLength);
            return capacity != 0
                ? capacity
                : a.networkAddress.compareTo(b.networkAddress);
          });
    final candidates = <AllocationRecommendation>[];
    for (final block in fitting) {
      if (candidates.length >= limit) break;
      final first = block.networkAddress;
      final last = block.lastAddress - size + BigInt.one;
      void add(BigInt address) {
        final cidr =
            Cidr.fromNetworkAddress(address, selectedPrefix, parent.version);
        final details = CidrDetails.from(cidr, policy: policy);
        candidates.add(AllocationRecommendation(
            cidr: cidr,
            details: details,
            rationale: _rationale(
                parent: parent,
                routingDomain: routingDomain,
                parentId: parentId,
                demand: demand,
                details: details,
                block: block,
                edge: address == first || address == last)));
      }

      add(first);
      if (last != first && candidates.length < limit) add(last);
      var address = first + size;
      while (address < last && candidates.length < limit) {
        add(address);
        address += size;
      }
    }
    final warnings = <String>[_coverageCaveat];
    if (freeSlots == BigInt.zero) {
      warnings.add(
          'No aligned /$selectedPrefix candidate is available in this inventory, '
          'even if individual free addresses remain.');
    } else if (freeSlots > BigInt.from(candidates.length)) {
      warnings.add(
          '${candidates.length} shown of $freeSlots available aligned /$selectedPrefix slots.');
    }
    return AllocationPlan(
        summary: summary,
        prefixLength: selectedPrefix,
        targetAddresses: demand?.targetAddresses,
        candidates: candidates,
        warnings: warnings);
  }

  static int _demandPrefix(
      Cidr parent, AddressDemand demand, AddressPolicy policy) {
    if (policy != AddressPolicy.ociIpv4Subnet || parent.version != 4) {
      throw ArgumentError(
          'Address demand sizing requires OCI IPv4 subnet policy and an IPv4 pool. '
          'Use an explicit prefix for generic or IPv6 planning.');
    }
    final minimum = parent.prefixLength > 16 ? parent.prefixLength : 16;
    for (var prefix = 30; prefix >= minimum; prefix--) {
      final capacity = (BigInt.one << (32 - prefix)) - BigInt.from(3);
      if (capacity >= demand.targetAddresses) return prefix;
    }
    throw ArgumentError(
        'No eligible OCI IPv4 subnet in ${parent.canonical} can fit '
        '${demand.targetAddresses} planned addresses after the explicit allowances.');
  }
}

const _coverageCaveat =
    'Available in this inventory; coverage and freshness are '
    'not proof of live vacancy. Recheck current inventory conflicts when reserving.';

String _rationale(
    {required Cidr parent,
    required String routingDomain,
    required String? parentId,
    required AddressDemand? demand,
    required CidrDetails details,
    required Cidr block,
    required bool edge}) {
  final cidr = details.cidr;
  final sizing = demand == null
      ? 'Requested prefix /${cidr.prefixLength}; no automatic growth was added.'
      : '${demand.addresses} ${demand.basis.name} address demand with '
          '${demand.growthPercent}% explicit growth and '
          '${demand.additionalAddresses} additional addresses requires '
          '${demand.targetAddresses} planned addresses. '
          '${details.assignableAddresses! - demand.targetAddresses} spare assignable '
          'addresses remain beyond those allowances. '
          '${_sizeComparison(parent, details, demand)}';
  final capacity = details.assignableAddresses == null
      ? '${details.totalAddresses} total addresses; provider assignable capacity is not assumed.'
      : '${details.totalAddresses} total and ${details.assignableAddresses} OCI assignable addresses.';
  return '${cidr.canonical} in pool ${parent.canonical}'
      '${parentId == null ? '' : ' (parent $parentId)'} and routing domain '
      '${routingDomain.trim()}. $sizing Policy: ${details.policy.name}. $capacity '
      'Best-fit placement prefers the smallest fitting maximal aligned free block; '
      '${block.canonical} is the containing free block. '
      '${edge ? 'Aligned edge placement' : 'Aligned alternative placement'} '
      'preserves larger free blocks, with address order breaking ties. '
      'This is a placement heuristic, not an optimal-packing guarantee. $_coverageCaveat';
}

String _sizeComparison(Cidr parent, CidrDetails details, AddressDemand demand) {
  final prefix = details.cidr.prefixLength;
  final comparisons = <String>[];
  if (prefix < 30) {
    final capacity = (BigInt.one << (32 - prefix - 1)) - BigInt.from(3);
    comparisons.add(
        'A smaller /${prefix + 1} supplies $capacity assignable addresses and does not fit.');
  }
  if (prefix > 16 && prefix > parent.prefixLength) {
    final capacity = (BigInt.one << (32 - prefix + 1)) - BigInt.from(3);
    comparisons
        .add('A larger /${prefix - 1} supplies $capacity assignable addresses '
            '(${capacity - demand.targetAddresses} spare after allowances).');
  }
  return comparisons.join(' ');
}

String _formatAddress(BigInt address, int version) =>
    Cidr.fromNetworkAddress(address, version == 4 ? 32 : 128, version)
        .canonical
        .split('/')
        .first;
