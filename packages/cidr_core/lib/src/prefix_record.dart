enum PrefixKind { allocation, vcn, subnet }

enum PrefixStatus { planned, reserved, active, retired }

const _unset = Object();

/// One CIDR record; a VCN with multiple blocks has one record per block.
final class PrefixRecord {
  const PrefixRecord({
    required this.id,
    required this.cidr,
    required this.name,
    required this.routingDomain,
    this.kind = PrefixKind.vcn,
    this.status = PrefixStatus.reserved,
    this.customer = '',
    this.tenancy = '',
    this.region = '',
    this.compartment = '',
    this.environment = '',
    this.owner = '',
    this.resourceId = '',
    this.vcnId = '',
    this.parentId = '',
    this.notes = '',
    this.source = '',
    this.verifiedAt,
  });

  final String id;
  final String cidr;
  final String name;
  final String routingDomain;
  final PrefixKind kind;
  final PrefixStatus status;
  final String customer;
  final String tenancy;
  final String region;
  final String compartment;
  final String environment;
  final String owner;
  final String resourceId;
  final String vcnId;
  final String parentId;
  final String notes;
  final String source;
  final DateTime? verifiedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'cidr': cidr,
        'name': name,
        'routingDomain': routingDomain,
        'kind': kind.name,
        'status': status.name,
        'customer': customer,
        'tenancy': tenancy,
        'region': region,
        'compartment': compartment,
        'environment': environment,
        'owner': owner,
        'resourceId': resourceId,
        'vcnId': vcnId,
        'parentId': parentId,
        'notes': notes,
        'source': source,
        'verifiedAt': verifiedAt?.toIso8601String(),
      };

  factory PrefixRecord.fromJson(Map<String, dynamic> json) {
    String field(String key, {bool required = false}) {
      final value = json[key];
      if (value == null && !required) return '';
      if (value is! String) {
        throw FormatException('Record field "$key" must be a string.');
      }
      return value;
    }

    T enumeration<T extends Enum>(String key, List<T> values, T fallback) {
      if (json[key] == null || json[key] == '') return fallback;
      for (final value in values) {
        if (value.name == json[key]) return value;
      }
      throw FormatException('Unknown $key: ${json[key]}.');
    }

    DateTime? verifiedAt;
    if (json['verifiedAt'] != null && json['verifiedAt'] != '') {
      verifiedAt = DateTime.tryParse(field('verifiedAt'));
      if (verifiedAt == null) {
        throw const FormatException('Invalid verifiedAt timestamp.');
      }
    }
    return PrefixRecord(
      id: field('id', required: true),
      cidr: field('cidr', required: true),
      name: field('name', required: true),
      routingDomain: field('routingDomain', required: true),
      kind: enumeration('kind', PrefixKind.values, PrefixKind.vcn),
      status: enumeration('status', PrefixStatus.values, PrefixStatus.reserved),
      customer: field('customer'),
      tenancy: field('tenancy'),
      region: field('region'),
      compartment: field('compartment'),
      environment: field('environment'),
      owner: field('owner'),
      resourceId: field('resourceId'),
      vcnId: field('vcnId'),
      parentId: field('parentId'),
      notes: field('notes'),
      source: field('source'),
      verifiedAt: verifiedAt,
    );
  }

  PrefixRecord copyWith({
    String? id,
    String? cidr,
    String? name,
    String? routingDomain,
    PrefixKind? kind,
    PrefixStatus? status,
    String? customer,
    String? tenancy,
    String? region,
    String? compartment,
    String? environment,
    String? owner,
    String? resourceId,
    String? vcnId,
    String? parentId,
    String? notes,
    String? source,
    Object? verifiedAt = _unset,
  }) =>
      PrefixRecord(
        id: id ?? this.id,
        cidr: cidr ?? this.cidr,
        name: name ?? this.name,
        routingDomain: routingDomain ?? this.routingDomain,
        kind: kind ?? this.kind,
        status: status ?? this.status,
        customer: customer ?? this.customer,
        tenancy: tenancy ?? this.tenancy,
        region: region ?? this.region,
        compartment: compartment ?? this.compartment,
        environment: environment ?? this.environment,
        owner: owner ?? this.owner,
        resourceId: resourceId ?? this.resourceId,
        vcnId: vcnId ?? this.vcnId,
        parentId: parentId ?? this.parentId,
        notes: notes ?? this.notes,
        source: source ?? this.source,
        verifiedAt: identical(verifiedAt, _unset)
            ? this.verifiedAt
            : verifiedAt as DateTime?,
      );
}
