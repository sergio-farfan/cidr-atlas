// CIDR Atlas
// Shared exact CIDR capacity, ranges, and containing-supernet inspector.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_core/cidr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Exact CIDR details shared by inventory and planning selections.
class CidrInspector extends StatefulWidget {
  const CidrInspector({
    super.key,
    required this.cidr,
    this.policy = AddressPolicy.generic,
  });
  final Cidr cidr;
  final AddressPolicy policy;

  @override
  State<CidrInspector> createState() => _CidrInspectorState();
}

class _CidrInspectorState extends State<CidrInspector> {
  int? _supernetPrefix;
  int? _childPrefix;

  @override
  void didUpdateWidget(covariant CidrInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cidr != widget.cidr) {
      _supernetPrefix = null;
      _childPrefix = null;
    }
  }

  Widget _field(String name, String value, {bool copy = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(color: Color(0xff98a6bc), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (copy)
              IconButton(
                tooltip: 'Copy $name',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 16),
                onPressed: () => Clipboard.setData(ClipboardData(text: value)),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cidr = widget.cidr;
    final details = CidrDetails.from(cidr, policy: widget.policy);
    final supernetPrefix = _supernetPrefix;
    final childPrefix =
        _childPrefix ??
        (cidr.version == 6 && cidr.prefixLength <= 64
            ? 64
            : (cidr.prefixLength + 1).clamp(0, cidr.bitLength));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _field('Network prefix', cidr.canonical, copy: true),
        _field('Address family', 'IPv${cidr.version}'),
        _field(
          'Prefix length',
          '/${cidr.prefixLength} network bits; ${details.hostBits} host bits',
        ),
        if (details.subnetMask != null)
          _field('Subnet mask', details.subnetMask!),
        _field(
          'Address range',
          '${details.firstAddress}\n${details.lastAddress}',
          copy: true,
        ),
        _field('Total addresses', formatAddressCount(details.totalAddresses)),
        if (details.assignableAddresses != null) ...[
          _field(
            'Provider capacity',
            '${formatAddressCount(details.assignableAddresses!)} assignable addresses',
          ),
          if (details.assignableFirst != null && details.assignableLast != null)
            _field(
              'Assignable range',
              '${details.assignableFirst}\n${details.assignableLast}',
            ),
        ],
        Text(
          details.policyNote,
          style: const TextStyle(fontSize: 12, color: Color(0xff98a6bc)),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<int>(
          key: ValueKey('inspector-child-${cidr.canonical}'),
          initialValue: childPrefix,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Child subnet size'),
          items: [
            for (var p = cidr.prefixLength; p <= cidr.bitLength; p++)
              DropdownMenuItem(value: p, child: Text('/$p')),
          ],
          onChanged: (value) => setState(() => _childPrefix = value),
        ),
        _field(
          'Aligned child slots before blockers',
          formatAddressCount(BigInt.one << (childPrefix - cidr.prefixLength)),
        ),
        const Text(
          'Free-slot counts require the selected pool and inventory.',
          style: TextStyle(fontSize: 12, color: Color(0xff98a6bc)),
        ),
        if (cidr.prefixLength > 0) ...[
          const SizedBox(height: 18),
          DropdownButtonFormField<int>(
            key: ValueKey('inspector-supernet-${cidr.canonical}'),
            initialValue: supernetPrefix,
            isExpanded: true,
            hint: const Text('Choose shorter prefix'),
            decoration: const InputDecoration(labelText: 'Containing supernet'),
            items: [
              for (var p = 0; p < cidr.prefixLength; p++)
                DropdownMenuItem(value: p, child: Text('/$p')),
            ],
            onChanged: (value) => setState(() => _supernetPrefix = value),
          ),
          if (supernetPrefix != null)
            _field(
              'Calculated containing supernet',
              details.containingSupernet(supernetPrefix).canonical,
              copy: true,
            ),
          const SizedBox(height: 8),
          const Text(
            'A calculated supernet does not authorize allocating its range.',
            style: TextStyle(fontSize: 12, color: Color(0xff98a6bc)),
          ),
        ],
      ],
    );
  }
}

/// Decimal grouping preserves exact values, including the full IPv6 space.
String formatAddressCount(BigInt value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
