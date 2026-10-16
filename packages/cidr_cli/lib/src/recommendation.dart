// CIDR Atlas
// Explainable recommendation previews and explicit atomic reservations.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:args/args.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';

void addRecommendationOptions(ArgParser parser) {
  parser
    ..addOption('pool', help: 'Required canonical CIDR planning boundary.')
    ..addOption('routing-domain', help: 'Required conflict-checking scope.')
    ..addOption('parent', help: 'Explicit inventory pool record id.')
    ..addOption('prefix',
        help: 'Requested prefix length; excludes --addresses.')
    ..addOption('addresses',
        help: 'Positive address demand; requires explicit --growth-percent.')
    ..addOption('growth-percent',
        help: 'Explicit nonnegative growth percentage, including zero.')
    ..addOption('additional',
        defaultsTo: '0', help: 'Separate nonnegative fixed address demand.')
    ..addOption('basis',
        allowed: ['current', 'peak'],
        defaultsTo: 'current',
        help: 'Whether demand is current or already planned peak demand.')
    ..addOption('policy',
        allowed: ['generic', 'oci_ipv4'],
        help: 'Defaults to generic for prefix, oci_ipv4 for address demand.')
    ..addOption('kind',
        allowed: ['vcn', 'subnet'],
        help: 'Defaults to VCN under an allocation; otherwise subnet.')
    ..addOption('limit',
        defaultsTo: '12', help: 'Positive candidate display limit.')
    ..addOption('format', allowed: ['text', 'json'], defaultsTo: 'text')
    ..addFlag('apply',
        negatable: false,
        help: 'Reserve the first ranked candidate locally; requires --name.')
    ..addOption('name', help: 'Reservation name, required with --apply.')
    ..addOption('notes',
        help: 'Optional notes; recommendation rationale is retained.');
}

int runRecommendation(InventoryStore store, ArgResults command,
    StringSink output, StringSink errors) {
  if (command.rest.isNotEmpty) {
    throw const FormatException(
        'recommend accepts options without positional arguments.');
  }
  final pool = Cidr.parse(_recommendationRequired(command, 'pool'));
  final domain = _recommendationRequired(command, 'routing-domain');
  final apply = command['apply'] as bool;
  final name = apply ? _recommendationRequired(command, 'name') : '';
  final parentId = command.wasParsed('parent')
      ? _recommendationRequired(command, 'parent')
      : null;
  final hasPrefix = command.wasParsed('prefix');
  final hasDemand = command.wasParsed('addresses');
  if (hasPrefix == hasDemand) {
    throw const FormatException(
        'Supply exactly one of --prefix or --addresses.');
  }
  if (!hasDemand &&
      ['growth-percent', 'additional', 'basis'].any(command.wasParsed)) {
    throw const FormatException(
        '--growth-percent, --additional, and --basis require --addresses.');
  }
  final limit = _recommendationInteger(command, 'limit', minimum: 1);
  final int? prefix;
  if (hasPrefix) {
    prefix =
        _recommendationInteger(command, 'prefix', minimum: pool.prefixLength);
    if (prefix > pool.bitLength) {
      throw FormatException(
          '--prefix must be at most ${pool.bitLength} for IPv${pool.version}.');
    }
  } else {
    prefix = null;
  }
  final policy = switch (command['policy'] as String?) {
    'generic' => AddressPolicy.generic,
    'oci_ipv4' => AddressPolicy.ociIpv4Subnet,
    _ => hasDemand ? AddressPolicy.ociIpv4Subnet : AddressPolicy.generic,
  };
  final AddressDemand? demand;
  if (hasDemand) {
    final addresses =
        _recommendationCount(command, 'addresses', minimum: BigInt.one);
    final growth =
        _recommendationInteger(command, 'growth-percent', minimum: 0);
    final additional =
        _recommendationCount(command, 'additional', minimum: BigInt.zero);
    if (policy != AddressPolicy.ociIpv4Subnet) {
      throw const FormatException('--addresses requires --policy oci_ipv4.');
    }
    demand = AddressDemand(
      addresses: addresses,
      growthPercent: growth,
      additionalAddresses: additional,
      basis: DemandBasis.values.byName(command['basis'] as String),
    );
  } else {
    demand = null;
  }
  final records = store.list();
  PrefixRecord? parent;
  for (final record in records) {
    if (record.id == parentId) parent = record;
  }
  final kind = command.wasParsed('kind')
      ? PrefixKind.values.byName(command['kind'] as String)
      : parent?.kind == PrefixKind.allocation
          ? PrefixKind.vcn
          : PrefixKind.subnet;
  if (policy == AddressPolicy.ociIpv4Subnet && kind != PrefixKind.subnet) {
    throw const FormatException(
        'OCI IPv4 subnet capacity requires --kind subnet. '
        'Use --prefix with generic policy for VCN planning.');
  }
  try {
    if (parent?.kind == PrefixKind.vcn && kind != PrefixKind.subnet) {
      throw ArgumentError(
          'A VCN parent can contain only subnet recommendations.');
    }
    final plan = AddressPlanner.plan(
      parent: pool,
      routingDomain: domain,
      records: records,
      parentId: parentId,
      prefixLength: prefix,
      demand: demand,
      policy: policy,
      limit: limit,
    );
    PrefixRecord? reserved;
    if (apply) {
      if (plan.candidates.isEmpty) {
        _writeRecommendation(plan, command, domain, kind, output);
        errors
            .writeln('No aligned /${plan.prefixLength} candidate is available '
                'in this inventory. No reservation was saved.');
        return 1;
      }
      final candidate = plan.candidates.first;
      final notes = (command['notes'] as String?)?.trim() ?? '';
      reserved = PrefixRecord(
        id: _recommendationId(records),
        cidr: candidate.cidr.canonical,
        name: name,
        routingDomain: domain,
        kind: kind,
        status: PrefixStatus.reserved,
        parentId: parentId ?? '',
        customer: parent?.customer ?? '',
        tenancy: parent?.tenancy ?? '',
        region: parent?.region ?? '',
        compartment: parent?.compartment ?? '',
        environment: parent?.environment ?? '',
        owner: parent?.owner ?? '',
        vcnId: parent?.kind == PrefixKind.vcn ? parent!.resourceId : '',
        notes: notes.isEmpty
            ? candidate.rationale
            : '$notes\n\n${candidate.rationale}',
        source: 'manual',
      );
      try {
        store.reserve(reserved);
      } on InventoryConflictException catch (error) {
        errors.writeln('Reservation was not saved: $error');
        return 3;
      } on FormatException catch (error) {
        errors.writeln('Reservation was not saved: ${error.message}');
        return 1;
      }
    }
    _writeRecommendation(plan, command, domain, kind, output,
        reserved: reserved);
    return 0;
  } on ArgumentError catch (error) {
    errors.writeln('Recommendation failed: ${error.message}');
    return 1;
  }
}

int _recommendationInteger(ArgResults command, String key,
    {required int minimum}) {
  final raw = _recommendationRequired(command, key);
  final value = RegExp(r'^[0-9]+$').hasMatch(raw) ? int.tryParse(raw) : null;
  if (value == null || value < minimum) {
    throw FormatException(
        '--$key must be a decimal integer of at least $minimum.');
  }
  return value;
}

BigInt _recommendationCount(ArgResults command, String key,
    {required BigInt minimum}) {
  final raw = _recommendationRequired(command, key);
  final value = RegExp(r'^[0-9]+$').hasMatch(raw) ? BigInt.tryParse(raw) : null;
  if (value == null || value < minimum) {
    throw FormatException(
        '--$key must be a decimal integer of at least $minimum.');
  }
  return value;
}

String _recommendationRequired(ArgResults command, String key) {
  final value = command[key] as String?;
  if (value == null || value.trim().isEmpty) {
    throw FormatException('--$key is required.');
  }
  return value.trim();
}

String _recommendationId(List<PrefixRecord> records) {
  final existing = records.map((record) => record.id).toSet();
  final base = 'local-${DateTime.now().microsecondsSinceEpoch}';
  var id = base;
  var suffix = 1;
  while (existing.contains(id)) {
    id = '$base-${suffix++}';
  }
  return id;
}

void _writeRecommendation(AllocationPlan plan, ArgResults command,
    String domain, PrefixKind kind, StringSink output,
    {PrefixRecord? reserved}) {
  if (command['format'] == 'json') {
    output.writeln(const JsonEncoder.withIndent('  ').convert({
      ...plan.toJson(),
      if (reserved != null) 'reservation': reserved.toJson(),
    }));
    return;
  }
  final summary = plan.summary;
  output
      .writeln('Pool: ${summary.parent.canonical} | Routing domain: $domain | '
          'Kind: ${kind.name}');
  output.writeln('Requested size: /${plan.prefixLength}'
      '${plan.targetAddresses == null ? '' : ' | Planned addresses: ${plan.targetAddresses}'}');
  output.writeln(
      '${summary.freeAddresses} of ${summary.totalAddresses} addresses '
      'available; ${summary.blockedAddresses} blocked.');
  output.writeln('${plan.candidates.length} shown of ${summary.freeSlots} '
      'available aligned /${plan.prefixLength} slots '
      '(${summary.totalSlots} total slots before blockers).');
  output.writeln(
      'Largest free block: ${summary.largestFreeBlock?.canonical ?? 'none'}.');
  for (var index = 0; index < plan.candidates.length; index++) {
    final candidate = plan.candidates[index];
    output.writeln('${index + 1}. ${candidate.cidr.canonical} | '
        '${candidate.details.totalAddresses} total addresses'
        '${candidate.details.assignableAddresses == null ? '' : ' | ${candidate.details.assignableAddresses} OCI assignable'}');
    output.writeln('   ${candidate.rationale}');
  }
  for (final warning in plan.warnings) {
    output.writeln('Warning: $warning');
  }
  if (reserved != null) {
    output.writeln('Reserved ${reserved.cidr} as ${reserved.name} '
        '[${reserved.id}] in ${reserved.routingDomain}.');
  } else {
    output.writeln('Preview only. Use --apply --name NAME to reserve the first '
        'ranked candidate locally.');
  }
}
