// CIDR Atlas
// Address-space hierarchy, bounded recommendations, and local reservation intent.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:math' as math;

import 'package:cidr_core/cidr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cidr_inspector.dart';

const _surface = Color(0xff171e2b);
const _border = Color(0xff293244);
const _muted = Color(0xff98a6bc);
const _accent = Color(0xff8fafff);
const _free = Color(0xff77d8b4);
const _blocked = Color(0xffdbc18b);

/// A local planning workspace. Every calculation uses the full inventory.
class VisualPlanner extends StatefulWidget {
  const VisualPlanner({
    super.key,
    required this.records,
    required this.onReserve,
  });
  final List<PrefixRecord> records;
  final void Function(PrefixRecord) onReserve;

  @override
  State<VisualPlanner> createState() => _VisualPlannerState();
}

class _VisualPlannerState extends State<VisualPlanner> {
  final _manualPool = TextEditingController(text: '10.0.0.0/8');
  final _manualDomain = TextEditingController();
  final _prefix = TextEditingController(text: '24');
  final _addresses = TextEditingController();
  final _growth = TextEditingController();
  final _additional = TextEditingController(text: '0');
  final _transform = TransformationController();
  final _candidateFocus = List.generate(12, (_) => FocusNode());
  String? _domain;
  String _poolId = '';
  PrefixKind _kind = PrefixKind.vcn;
  AddressPolicy _policy = AddressPolicy.generic;
  DemandBasis _basis = DemandBasis.current;
  bool _demandMode = false;
  AllocationPlan? _result;
  int _selected = 0;
  int _rangePage = 0;
  String? _error;
  PrefixRecord? _inspected;
  late String _inventorySignature;

  String _signature() =>
      jsonEncode(widget.records.map((r) => r.toJson()).toList());
  String get _routingDomain =>
      _domain == '__manual__' ? _manualDomain.text.trim() : (_domain ?? '');
  PrefixRecord? get _pool => widget.records
      .where(
        (r) =>
            r.id == _poolId &&
            r.status != PrefixStatus.retired &&
            r.kind != PrefixKind.subnet &&
            r.routingDomain == _routingDomain,
      )
      .firstOrNull;
  AllocationRecommendation? get _candidate =>
      _result == null || _result!.candidates.isEmpty
      ? null
      : _result!.candidates[_selected];

  @override
  void initState() {
    super.initState();
    _inventorySignature = _signature();
    for (final controller in [
      _manualPool,
      _manualDomain,
      _prefix,
      _addresses,
      _growth,
      _additional,
    ]) {
      controller.addListener(_invalidate);
    }
  }

  @override
  void didUpdateWidget(covariant VisualPlanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature();
    if (signature != _inventorySignature) {
      _inventorySignature = signature;
      _clear();
      _inspected = null;
      if (_poolId.isNotEmpty && _pool == null) _poolId = '';
    }
  }

  void _clear() {
    _result = null;
    _error = null;
    _selected = 0;
    _rangePage = 0;
  }

  void _invalidate() => setState(_clear);

  void _change(VoidCallback change) => setState(() {
    _clear();
    change();
  });

  @override
  void dispose() {
    for (final controller in [
      _manualPool,
      _manualDomain,
      _prefix,
      _addresses,
      _growth,
      _additional,
    ]) {
      controller.removeListener(_invalidate);
      controller.dispose();
    }
    _transform.dispose();
    for (final focus in _candidateFocus) {
      focus.dispose();
    }
    super.dispose();
  }

  void _choosePool(PrefixRecord? pool) {
    _change(() {
      _poolId = pool?.id ?? '';
      _inspected = pool;
      if (pool != null) {
        _domain = pool.routingDomain;
        _kind = pool.kind == PrefixKind.vcn
            ? PrefixKind.subnet
            : PrefixKind.vcn;
        if (_kind != PrefixKind.subnet) {
          _policy = AddressPolicy.generic;
          _demandMode = false;
        }
      }
    });
    _transform.value = Matrix4.identity();
  }

  void _calculate() {
    try {
      if (_routingDomain.isEmpty)
        throw const FormatException(
          'Choose a routing domain, or enter an explicit domain manually.',
        );
      final pool = _pool;
      if (_poolId.isNotEmpty && pool == null)
        throw const FormatException('Select an existing, non-retired pool.');
      final parent = Cidr.parse(pool?.cidr ?? _manualPool.text);
      if (pool?.kind == PrefixKind.vcn && _kind != PrefixKind.subnet)
        throw const FormatException('A VCN pool requires subnet intent.');
      if (pool?.kind == PrefixKind.allocation && _kind != PrefixKind.vcn)
        throw const FormatException('An allocation pool requires VCN intent.');
      if (_policy == AddressPolicy.ociIpv4Subnet &&
          (_kind != PrefixKind.subnet || parent.version != 4))
        throw const FormatException(
          'OCI IPv4 subnet policy requires IPv4 and subnet intent.',
        );
      AddressDemand? demand;
      int? prefix;
      if (_demandMode) {
        if (_kind != PrefixKind.subnet ||
            _policy != AddressPolicy.ociIpv4Subnet ||
            parent.version != 4)
          throw const FormatException(
            'Address demand requires OCI IPv4 subnet policy and subnet intent. Plan VCNs from their child subnet requirements.',
          );
        final base = BigInt.tryParse(_addresses.text.trim());
        final growth = int.tryParse(_growth.text.trim());
        final additional = BigInt.tryParse(_additional.text.trim());
        if (base == null || growth == null || additional == null)
          throw const FormatException(
            'Enter whole address counts and choose an explicit growth percentage, including 0 if deliberate.',
          );
        demand = AddressDemand(
          addresses: base,
          growthPercent: growth,
          additionalAddresses: additional,
          basis: _basis,
        );
      } else {
        prefix = int.tryParse(_prefix.text.trim());
        if (prefix == null)
          throw const FormatException('Enter a whole prefix length.');
        if (_policy == AddressPolicy.ociIpv4Subnet &&
            (prefix < 16 || prefix > 30))
          throw const FormatException(
            'OCI IPv4 subnets require /16 through /30. Use generic policy for raw /31 or /32 calculations.',
          );
      }
      final result = AddressPlanner.plan(
        parent: parent,
        routingDomain: _routingDomain,
        records: widget.records,
        parentId: pool?.id,
        prefixLength: prefix,
        demand: demand,
        policy: _policy,
        limit: 12,
      );
      setState(() {
        _result = result;
        _selected = 0;
        _rangePage = 0;
        _inspected = null;
        _error = null;
      });
      _transform.value = Matrix4.identity();
    } catch (error) {
      setState(() {
        _clear();
        _error = _errorText(error);
      });
    }
  }

  String _errorText(Object error) => error is FormatException
      ? error.message.toString()
      : error.toString().replaceFirst(
          RegExp(r'^(Invalid argument\(s\)?: |Bad state: )'),
          '',
        );

  void _reserve() {
    final candidate = _candidate;
    if (candidate == null) return;
    final parent = _pool;
    final existingIds = widget.records.map((r) => r.id).toSet();
    final baseId = 'reservation-${DateTime.now().microsecondsSinceEpoch}';
    var id = baseId;
    var suffix = 0;
    while (existingIds.contains(id)) {
      id = '$baseId-${++suffix}';
    }
    widget.onReserve(
      PrefixRecord(
        id: id,
        cidr: candidate.cidr.canonical,
        name: 'Planned ${_kind == PrefixKind.vcn ? 'VCN' : 'subnet'}',
        routingDomain: _routingDomain,
        kind: _kind,
        status: PrefixStatus.reserved,
        parentId: parent?.id ?? '',
        customer: parent?.customer ?? '',
        tenancy: parent?.tenancy ?? '',
        region: parent?.region ?? '',
        compartment: parent?.compartment ?? '',
        environment: parent?.environment ?? '',
        owner: parent?.owner ?? '',
        vcnId: parent?.kind == PrefixKind.vcn ? parent!.resourceId : '',
        notes: candidate.rationale,
        source: 'local planning',
      ),
    );
  }

  Widget _panel(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(18),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _surface,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Material(color: Colors.transparent, child: child),
  );

  Widget _select<T>({
    required String keyName,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) => DropdownButtonFormField<T>(
    key: ValueKey(keyName),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    hint: hint == null ? null : Text(hint),
    items: items,
    onChanged: onChanged,
  );

  Widget _number(
    String keyName,
    String label,
    TextEditingController controller, {
    String? hint,
  }) => TextField(
    key: ValueKey(keyName),
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

  Widget _controls(double width) {
    final domains =
        widget.records
            .map((r) => r.routingDomain)
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_domain != null &&
        _domain != '__manual__' &&
        !domains.contains(_domain))
      domains.add(_domain!);
    final pools = widget.records
        .where(
          (r) =>
              r.routingDomain == _routingDomain &&
              r.kind != PrefixKind.subnet &&
              r.status != PrefixStatus.retired,
        )
        .toList();
    final fieldWidth = width < 550 ? width : (width - 24) / 3;
    Widget field(Widget child, {bool wide = false}) => SizedBox(
      width: wide && width >= 550 ? fieldWidth * 2 + 12 : fieldWidth,
      child: child,
    );
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              field(
                _select<String>(
                  keyName: 'planner-domain',
                  label: 'Routing domain',
                  value: _domain,
                  hint: 'Choose routing domain',
                  items: [
                    for (final d in domains)
                      DropdownMenuItem(
                        value: d,
                        child: Text(d, overflow: TextOverflow.ellipsis),
                      ),
                    const DropdownMenuItem(
                      value: '__manual__',
                      child: Text('Enter domain manually'),
                    ),
                  ],
                  onChanged: (value) => _change(() {
                    _domain = value;
                    _poolId = '';
                    _inspected = null;
                  }),
                ),
              ),
              field(
                _select<String>(
                  keyName: 'planner-pool',
                  label: 'Allocation or VCN pool',
                  value: _poolId,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Enter a range manually'),
                    ),
                    for (final p in pools)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.name} (${p.cidr})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) =>
                      _choosePool(pools.where((r) => r.id == id).firstOrNull),
                ),
                wide: true,
              ),
              if (_domain == '__manual__')
                field(
                  TextField(
                    key: const ValueKey('planner-manual-domain'),
                    controller: _manualDomain,
                    decoration: const InputDecoration(
                      labelText: 'Explicit routing domain',
                      hintText: 'corporate-connected',
                    ),
                  ),
                ),
              if (_poolId.isEmpty)
                field(
                  TextField(
                    key: const ValueKey('planner-manual-pool'),
                    controller: _manualPool,
                    decoration: const InputDecoration(
                      labelText: 'Manual pool CIDR',
                    ),
                  ),
                ),
              field(
                _select<PrefixKind>(
                  keyName: 'planner-kind',
                  label: 'Resource to reserve',
                  value: _kind,
                  items: [
                    for (final k in [PrefixKind.vcn, PrefixKind.subnet])
                      DropdownMenuItem(
                        value: k,
                        child: Text(k == PrefixKind.vcn ? 'VCN' : 'Subnet'),
                      ),
                  ],
                  onChanged: (value) => _change(() {
                    _kind = value!;
                    if (_kind == PrefixKind.vcn) {
                      _demandMode = false;
                      _policy = AddressPolicy.generic;
                    }
                  }),
                ),
              ),
              field(
                _select<bool>(
                  keyName: 'planner-mode',
                  label: 'Sizing mode',
                  value: _demandMode,
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('Choose by prefix'),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text('Size from address demand'),
                    ),
                  ],
                  onChanged: (value) => _change(() {
                    _demandMode = value!;
                    if (_demandMode) {
                      _policy = AddressPolicy.ociIpv4Subnet;
                    }
                  }),
                ),
              ),
              field(
                _select<AddressPolicy>(
                  keyName: 'planner-policy',
                  label: 'Address policy',
                  value: _policy,
                  items: const [
                    DropdownMenuItem(
                      value: AddressPolicy.generic,
                      child: Text('Generic exact capacity'),
                    ),
                    DropdownMenuItem(
                      value: AddressPolicy.ociIpv4Subnet,
                      child: Text('OCI IPv4 subnet'),
                    ),
                  ],
                  onChanged: (value) => _change(() => _policy = value!),
                ),
              ),
              if (!_demandMode)
                field(
                  _number(
                    'planner-prefix',
                    'Requested prefix length',
                    _prefix,
                    hint: '24',
                  ),
                ),
              if (_demandMode) ...[
                field(
                  _select<DemandBasis>(
                    keyName: 'planner-basis',
                    label: 'Demand basis',
                    value: _basis,
                    items: const [
                      DropdownMenuItem(
                        value: DemandBasis.current,
                        child: Text('Current address demand'),
                      ),
                      DropdownMenuItem(
                        value: DemandBasis.peak,
                        child: Text('Already planned peak'),
                      ),
                    ],
                    onChanged: (value) => _change(() => _basis = value!),
                  ),
                ),
                field(
                  _number('planner-demand', 'Endpoint IP demand', _addresses),
                ),
                field(
                  _number(
                    'planner-growth',
                    'Explicit growth allowance (%)',
                    _growth,
                    hint: 'Choose a percentage, including 0',
                  ),
                ),
                field(
                  _number(
                    'planner-additional',
                    'Additional service / HA / DR IPs',
                    _additional,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _demandMode
                ? 'Enter IP demand directly. Growth is applied once to the selected demand basis. Additional IPs must exclude demand already counted above.'
                : 'The routing domain is the overlap-check scope for connected address plans. Every non-retired range in this domain is checked.',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('planner-calculate'),
            onPressed: _calculate,
            icon: const Icon(Icons.manage_search, size: 18),
            label: const Text('Find available space'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xffffb4ab)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth - 40;
      final wide = width >= 1160;
      return SingleChildScrollView(
        key: const ValueKey('planner-scroll'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Address Space',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose an explicit pool. Inspect capacity, compare available blocks, and reserve locally.',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 16),
            _controls(math.max(0, width - 36)),
            const SizedBox(height: 16),
            _coverage(),
            const SizedBox(height: 16),
            if (width < 650) ...[
              _hierarchy(),
              const SizedBox(height: 16),
              _workspace(wide: false),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: wide ? 250 : 220, child: _hierarchy()),
                  const SizedBox(width: 16),
                  Expanded(child: _workspace(wide: wide)),
                  if (wide && (_candidate != null || _inspected != null)) ...[
                    const SizedBox(width: 16),
                    SizedBox(width: 290, child: _panel(_details())),
                  ],
                ],
              ),
          ],
        ),
      );
    },
  );

  Widget _coverage() {
    final relevant = widget.records
        .where(
          (r) => _routingDomain.isEmpty || r.routingDomain == _routingDomain,
        )
        .toList();
    final observed = relevant.where((r) => r.source == 'oci').toList();
    final dates =
        observed.map((r) => r.verifiedAt).whereType<DateTime>().toList()
          ..sort();
    final evidence = observed.isEmpty
        ? 'Observation coverage is unknown.'
        : dates.isEmpty
        ? 'OCI observation time is unknown.'
        : 'Oldest known OCI observation: ${dates.first.toUtc().toIso8601String()}. ${observed.where((r) => r.verifiedAt == null).length} OCI records have unknown observation time.';
    return _panel(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: _blocked),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Available in this inventory. $evidence Coverage is partial or unverified; missing observations do not release address space.',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
    );
  }

  Widget _workspace({required bool wide}) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_inspected != null && !wide)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: _showDetails,
              icon: const Icon(Icons.info_outline, size: 18),
              label: Text('Inspect ${_inspected!.cidr}'),
            ),
          ),
        if (result == null)
          _panel(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan within a known boundary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 12),
                Text(
                  'Select a routing domain and pool, then find available space. Input and inventory changes clear old recommendations.',
                  style: TextStyle(color: _muted),
                ),
                SizedBox(height: 12),
                Text(
                  'Hierarchy shows allocation ancestry and OCI membership. It does not establish network connectivity.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          )
        else ...[
          _summary(result),
          const SizedBox(height: 16),
          _addressMap(result),
          const SizedBox(height: 16),
          _recommendations(result, wide: wide),
        ],
      ],
    );
  }

  Widget _summary(AllocationPlan result) {
    final s = result.summary;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            s.parent.canonical,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _stat('Total addresses', s.totalAddresses),
              _stat('Blocked addresses', s.blockedAddresses),
              _stat('Free addresses', s.freeAddresses),
              _stat('Total /${result.prefixLength} slots', s.totalSlots),
              _stat('Available aligned slots', s.freeSlots),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Largest free aligned block: ${s.largestFreeBlock?.canonical ?? 'none'}. Partially occupied slots are unavailable.',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          if (result.targetAddresses != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${formatAddressCount(result.targetAddresses!)} planned capacity units, including the explicit allowances.',
              ),
            ),
          for (final warning in result.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                warning,
                style: const TextStyle(fontSize: 12, color: _blocked),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, BigInt count) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(height: 4),
        SelectableText(
          formatAddressCount(count),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  void _zoom(double factor) {
    final value = _transform.value.clone();
    final current = value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 12.0);
    value.scaleByDouble(next / current, next / current, 1, 1);
    _transform.value = value;
  }

  Widget _addressMap(AllocationPlan result) {
    final s = result.summary;
    final ranges = [
      for (final i in s.freeIntervals) (interval: i, free: true),
      for (final i in s.blockedIntervals) (interval: i, free: false),
    ]..sort((a, b) => a.interval.start.compareTo(b.interval.start));
    final shown = ranges.skip(_rangePage * 8).take(8).toList();
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              const Text(
                'Ordered address map',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: () => _zoom(1 / 1.5),
                icon: const Icon(Icons.remove, size: 18),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: () => _zoom(1.5),
                icon: const Icon(Icons.add, size: 18),
              ),
              TextButton(
                onPressed: () => _transform.value = Matrix4.identity(),
                child: const Text('Fit'),
              ),
              IconButton(
                tooltip: 'Reset view',
                onPressed: () => _transform.value = Matrix4.identity(),
                icon: const Icon(Icons.restart_alt, size: 18),
              ),
            ],
          ),
          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text('○ Free', style: TextStyle(color: _free)),
              Text('▧ Blocked', style: TextStyle(color: _blocked)),
              Text('□ Candidate', style: TextStyle(color: _accent)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: LayoutBuilder(
              builder: (context, constraints) => InteractiveViewer(
                transformationController: _transform,
                alignment: Alignment.topLeft,
                minScale: 1,
                maxScale: 12,
                boundaryMargin: const EdgeInsets.all(30),
                child: Semantics(
                  label: 'Address space in ascending address order. Free ranges are solid; blocked ranges are hatched. Candidate has an outlined marker.',
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 110),
                    painter: _AddressMapPainter(
                      summary: s,
                      candidate: _candidate?.cidr,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Text(
            'Drag to pan; pinch or use zoom controls. Small spans use a minimum visible marker.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          for (final entry in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      entry.free ? '○ Free' : '▧ Blocked',
                      style: TextStyle(
                        color: entry.free ? _free : _blocked,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      '${entry.interval.firstAddress} – ${entry.interval.lastAddress}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (ranges.length > 8)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  '${_rangePage * 8 + 1}–${_rangePage * 8 + shown.length} of ${ranges.length} intervals',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                IconButton(
                  tooltip: 'Previous intervals',
                  onPressed: _rangePage == 0
                      ? null
                      : () => setState(() => _rangePage--),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next intervals',
                  onPressed: (_rangePage + 1) * 8 >= ranges.length
                      ? null
                      : () => setState(() => _rangePage++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _recommendations(AllocationPlan result, {required bool wide}) {
    final candidate = _candidate;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available in this inventory',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${result.candidates.length} shown of ${result.summary.freeSlots} candidates',
            key: const ValueKey('candidate-count'),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (candidate == null)
            const Text(
              'No aligned block of the requested size fits. Choose a smaller block or another pool; required demand will not be reduced.',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < result.candidates.length; index++)
                OutlinedButton(
                  key: ValueKey('candidate-$index'),
                  focusNode: _candidateFocus[index],
                  style: OutlinedButton.styleFrom(
                    backgroundColor: index == _selected
                        ? const Color(0xff263958)
                        : null,
                    side: BorderSide(
                      color: index == _selected ? _accent : _border,
                    ),
                  ),
                  onPressed: () => setState(() {
                    _selected = index;
                    _inspected = null;
                  }),
                  child: Text(result.candidates[index].cidr.canonical),
                ),
            ],
          ),
          if (candidate != null) ...[
            const SizedBox(height: 18),
            Text(
              'Selected candidate ${_selected + 1}',
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatAddressCount(candidate.details.totalAddresses)} total${candidate.details.assignableAddresses == null ? '' : '; ${formatAddressCount(candidate.details.assignableAddresses!)} assignable'} addresses',
            ),
            if (result.targetAddresses != null &&
                candidate.details.assignableAddresses != null)
              Text(
                '${formatAddressCount(candidate.details.assignableAddresses! - result.targetAddresses!)} remaining beyond the chosen allowances',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            const SizedBox(height: 12),
            SelectableText(
              candidate.rationale,
              style: const TextStyle(fontSize: 12, height: 1.5, color: _muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const ValueKey('reserve-candidate'),
                  onPressed: _reserve,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Reserve selected CIDR'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: candidate.cidr.canonical),
                  ),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy CIDR'),
                ),
                if (!wide)
                  OutlinedButton.icon(
                    onPressed: _showDetails,
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: const Text('Inspect CIDR'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Reservation opens a reviewable local record. Availability is rechecked when the reservation is saved.',
              style: TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  void _showDetails() => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _details(),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _details() {
    final record = _inspected;
    final cidr = record != null ? Cidr.parse(record.cidr) : _candidate?.cidr;
    if (cidr == null)
      return const Text('Select a prefix or candidate to inspect.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          record?.name ?? 'Candidate details',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (record != null) ...[
          const SizedBox(height: 12),
          Text(
            '${_kindLabel(record.kind)} · ${record.status.name}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          SelectableText(
            'Routing domain: ${record.routingDomain}\nParent: ${record.parentId.isEmpty ? 'No explicit parent' : record.parentId}\nOwner: ${record.owner.isEmpty ? 'Unspecified' : record.owner}\nEnvironment: ${record.environment.isEmpty ? 'Unspecified' : record.environment}\nSource: ${record.source.isEmpty ? 'Unspecified' : record.source}\nObserved: ${record.verifiedAt?.toUtc().toIso8601String() ?? 'Unknown'}\nTenancy: ${record.tenancy}\nRegion: ${record.region}\nCompartment: ${record.compartment}',
            style: const TextStyle(fontSize: 12, height: 1.5, color: _muted),
          ),
          if (record.resourceId.isNotEmpty)
            SelectableText(
              'Resource: ${record.resourceId}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          if (record.vcnId.isNotEmpty)
            SelectableText(
              'VCN: ${record.vcnId}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          if (record.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SelectableText(
                record.notes,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
        const SizedBox(height: 12),
        CidrInspector(
          cidr: cidr,
          policy: record == null
              ? _policy
              : record.source == 'oci' && record.kind == PrefixKind.subnet
              ? AddressPolicy.ociIpv4Subnet
              : AddressPolicy.generic,
        ),
      ],
    );
  }

  String _kindLabel(PrefixKind kind) => switch (kind) {
    PrefixKind.allocation => 'Allocation',
    PrefixKind.vcn => 'VCN',
    PrefixKind.subnet => 'Subnet',
  };

  String _groupKey(PrefixRecord r) =>
      r.kind == PrefixKind.vcn && r.resourceId.isNotEmpty
      ? 'vcn:${r.routingDomain}:${r.tenancy}:${r.region}:${r.resourceId}'
      : 'prefix:${r.id}';

  bool _validParent(PrefixRecord parent, PrefixRecord child) =>
      InventoryRules.validate([
        parent.copyWith(parentId: ''),
        child.copyWith(parentId: parent.id),
      ]).isEmpty;

  PrefixRecord? _parentOf(PrefixRecord record, List<PrefixRecord> records) {
    if (record.parentId.isNotEmpty) {
      final parent = records.where((r) => r.id == record.parentId).firstOrNull;
      return parent != null && _validParent(parent, record) ? parent : null;
    }
    if (record.kind != PrefixKind.subnet || record.vcnId.isEmpty) return null;
    return records
        .where(
          (r) =>
              r.kind == PrefixKind.vcn &&
              r.resourceId == record.vcnId &&
              r.tenancy == record.tenancy &&
              r.region == record.region &&
              _validParent(r, record),
        )
        .firstOrNull;
  }

  Widget _hierarchy() {
    final records = widget.records
        .where(
          (r) => _routingDomain.isEmpty || r.routingDomain == _routingDomain,
        )
        .toList();
    final groups = <String, List<PrefixRecord>>{};
    for (final r in records) {
      groups.putIfAbsent(_groupKey(r), () => []).add(r);
    }
    for (final group in groups.values) {
      group.sort((a, b) => a.cidr.compareTo(b.cidr));
    }
    final parents = <String, String?>{};
    for (final entry in groups.entries) {
      final possible = entry.value.map((r) {
        final p = _parentOf(r, records);
        return p == null ? null : _groupKey(p);
      }).toSet();
      parents[entry.key] = possible.length == 1 && possible.single != entry.key
          ? possible.single
          : null;
    }
    final conflicts = <String>{};
    try {
      for (final conflict in InventoryRules.conflicts(widget.records)) {
        conflicts.add(conflict.first.id);
        conflicts.add(conflict.second.id);
      }
    } on FormatException {
      /* Malformed records remain visible in the hierarchy. */
    }
    final rendered = <String>{};
    Widget branch(String key, Set<String> ancestors) {
      final group = groups[key]!;
      final first = group.first;
      rendered.add(key);
      final children = groups.keys
          .where((k) => parents[k] == key && !ancestors.contains(k))
          .toList();
      final unresolved = group.any(
        (r) =>
            (r.parentId.isNotEmpty ||
                r.kind == PrefixKind.subnet && r.vcnId.isNotEmpty) &&
            _parentOf(r, records) == null,
      );
      final badges = group.map((r) => r.status.name).toSet().join(', ');
      return ExpansionTile(
        key: first.resourceId.isEmpty
            ? ValueKey('hierarchy-${first.id}')
            : ValueKey('resource-$key'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.only(left: 12),
        initiallyExpanded: true,
        title: Text(
          first.name,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_kindLabel(first.kind)}${group.length > 1 ? ' · ${group.length} CIDRs' : ''}\n$badges${group.any((r) => conflicts.contains(r.id)) ? '\nConflict: overlapping records' : ''}${unresolved ? '\n${first.parentId.isNotEmpty ? 'Unresolved explicit parent' : 'Unresolved VCN context'}' : ''}',
          style: TextStyle(
            fontSize: 10,
            color: unresolved || group.any((r) => conflicts.contains(r.id))
                ? _blocked
                : _muted,
          ),
        ),
        children: [
          for (final r in group)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 4),
              title: Text(r.cidr, style: const TextStyle(fontSize: 11)),
              subtitle: Text(
                '${r.status.name}${conflicts.contains(r.id) ? ' · Conflict' : ''}',
                style: const TextStyle(fontSize: 10),
              ),
              onTap: () => setState(() => _inspected = r),
              trailing:
                  r.kind == PrefixKind.subnet ||
                      r.status == PrefixStatus.retired
                  ? null
                  : IconButton(
                      tooltip: 'Use ${r.cidr} as pool',
                      icon: const Icon(Icons.input, size: 16),
                      onPressed: () => _choosePool(r),
                    ),
            ),
          for (final child in children) branch(child, {...ancestors, key}),
        ],
      );
    }

    final branches = <Widget>[];
    for (final key in groups.keys.where((k) => parents[k] == null)) {
      branches.add(branch(key, {}));
    }
    for (final key in groups.keys.where((k) => !rendered.contains(k))) {
      branches.add(branch(key, {}));
    }
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Resource hierarchy',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'No records in this scope. Add a pool or enter a manual range.',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
          ...branches,
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Active, reserved, and planned ranges block. Retired ranges remain visible. Relationships describe ancestry or OCI membership.',
              style: TextStyle(fontSize: 11, color: _muted),
            ),
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    );
  }
}

class _AddressMapPainter extends CustomPainter {
  const _AddressMapPainter({required this.summary, required this.candidate});
  final AddressSpaceSummary summary;
  final Cidr? candidate;

  @override
  void paint(Canvas canvas, Size size) {
    final left = summary.parent.networkAddress;
    final total = summary.totalAddresses;
    double x(BigInt address) =>
        ((address - left).toDouble() / total.toDouble() * size.width).clamp(
          0,
          size.width,
        );
    const top = 20.0;
    const height = 56.0;
    for (final interval in summary.freeIntervals) {
      canvas.drawRect(
        Rect.fromLTWH(
          x(interval.start),
          top,
          math.max(1, x(interval.end + BigInt.one) - x(interval.start)),
          height,
        ),
        Paint()..color = _free.withValues(alpha: 0.45),
      );
    }
    for (final interval in summary.blockedIntervals) {
      final rect = Rect.fromLTWH(
        x(interval.start),
        top,
        math.max(2, x(interval.end + BigInt.one) - x(interval.start)),
        height,
      );
      canvas.save();
      canvas.clipRect(rect);
      canvas.drawRect(rect, Paint()..color = _blocked.withValues(alpha: 0.35));
      for (var d = rect.left - height; d < rect.right; d += 10) {
        canvas.drawLine(
          Offset(d, top + height),
          Offset(d + height, top),
          Paint()
            ..color = _blocked.withValues(alpha: 0.65)
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
    }
    final selected = candidate;
    if (selected != null) {
      final start = x(selected.networkAddress);
      final width = math.max(4.0, x(selected.lastAddress + BigInt.one) - start);
      final rect = Rect.fromLTWH(
        math.min(start, math.max(0, size.width - width)),
        top - 4,
        width,
        height + 8,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawLine(
        Offset(rect.left, top - 12),
        Offset(rect.left + 6, top - 4),
        Paint()
          ..color = _accent
          ..strokeWidth = 2,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, height),
      Paint()
        ..color = _border
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _AddressMapPainter oldDelegate) =>
      oldDelegate.summary != summary || oldDelegate.candidate != candidate;
}
