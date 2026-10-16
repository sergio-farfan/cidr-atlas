import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:csv/csv.dart';

class ImportPreview {
  ImportPreview({
    required List<PrefixRecord> records,
    List<String> errors = const [],
    List<String> warnings = const [],
    required this.source,
  })  : records = List.unmodifiable(records),
        errors = List.unmodifiable(errors),
        warnings = List.unmodifiable(warnings);

  final List<PrefixRecord> records;
  final List<String> errors;
  final List<String> warnings;
  final String source;
  bool get canApply => records.isNotEmpty && errors.isEmpty;
}

abstract final class InventoryImport {
  static const columns = <String>[
    'id',
    'cidr',
    'name',
    'routingDomain',
    'kind',
    'status',
    'customer',
    'tenancy',
    'region',
    'compartment',
    'environment',
    'owner',
    'resourceId',
    'vcnId',
    'parentId',
    'notes',
    'source',
    'verifiedAt',
  ];

  static ImportPreview csv(String input,
      {List<PrefixRecord> existingRecords = const []}) {
    final records = <PrefixRecord>[];
    final errors = <String>[];
    try {
      final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
      if (text.trim().isEmpty) throw const FormatException('CSV is empty.');
      final rows = CsvToListConverter(
        shouldParseNumbers: false,
        allowInvalid: false,
        eol: _lineEnding(text),
      ).convert(text);
      if (rows.isEmpty) throw const FormatException('CSV has no header.');
      final known = {for (final name in columns) _header(name): name};
      final headers = <String>[];
      final seen = <String>{};
      for (final value in rows.first) {
        final raw = value.toString().trim();
        final key = known[_header(raw)];
        if (key == null) {
          errors.add('Unknown CSV column "$raw".');
          headers.add(raw);
        } else {
          if (!seen.add(key)) errors.add('Duplicate CSV column "$key".');
          headers.add(key);
        }
      }
      for (final required in ['cidr', 'name', 'routingDomain']) {
        if (!seen.contains(required))
          errors.add('Missing required CSV column "$required".');
      }
      if (errors.isNotEmpty)
        return ImportPreview(records: records, errors: errors, source: 'CSV');
      for (var index = 1; index < rows.length; index++) {
        final row = rows[index];
        if (row.every((cell) => cell.toString().trim().isEmpty)) continue;
        if (row.length > headers.length) {
          errors.add(
            'CSV row ${index + 1} has ${row.length} fields but the header has ${headers.length}.',
          );
          continue;
        }
        final fields = <String, dynamic>{};
        for (var cell = 0; cell < headers.length; cell++) {
          final value = cell < row.length ? row[cell].toString() : '';
          fields[headers[cell]] =
              headers[cell] == 'notes' ? value : value.trim();
        }
        try {
          records.add(_record(fields, origin: 'csv'));
        } catch (error) {
          errors.add('CSV row ${index + 1}: ${_message(error)}');
        }
      }
    } catch (error) {
      errors.add(_message(error));
    }
    return _preview(records, errors,
        source: 'CSV', existingRecords: existingRecords);
  }

  static ImportPreview json(String input,
      {required String routingDomain,
      List<PrefixRecord> existingRecords = const []}) {
    try {
      final decoded = jsonDecode(input);
      if (decoded is! Map)
        throw const FormatException('JSON root must be an object.');
      final root = Map<String, dynamic>.from(decoded);
      if (root.containsKey('format') ||
          root.containsKey('records') ||
          root.containsKey('version')) {
        return _backup(root, existingRecords);
      }
      if (routingDomain.trim().isEmpty) {
        throw const FormatException(
          'An explicit routing domain is required for OCI JSON imports.',
        );
      }
      return _oci(root, routingDomain.trim(), existingRecords);
    } catch (error) {
      return ImportPreview(
        records: const [],
        errors: [_message(error)],
        source: 'JSON',
      );
    }
  }

  static String exportCsv(List<PrefixRecord> records) {
    return const ListToCsvConverter(eol: '\r\n').convert([
      columns,
      for (final record in records)
        [for (final column in columns) record.toJson()[column] ?? ''],
    ]);
  }

  static String exportJson(List<PrefixRecord> records) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'cidr-atlas',
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'records': records.map((record) => record.toJson()).toList(),
      });

  static ImportPreview _backup(
      Map<String, dynamic> root, List<PrefixRecord> existingRecords) {
    if (root['format'] != 'cidr-atlas' || root['version'] != 1) {
      throw const FormatException(
        'Unsupported backup format or version; expected cidr-atlas version 1.',
      );
    }
    final values = root['records'];
    if (values is! List)
      throw const FormatException('Backup records must be an array.');
    final records = <PrefixRecord>[];
    final errors = <String>[];
    for (var i = 0; i < values.length; i++) {
      try {
        if (values[i] is! Map)
          throw const FormatException('Record must be an object.');
        records.add(
          _record(
            Map<String, dynamic>.from(values[i] as Map),
            origin: 'backup',
          ),
        );
      } catch (error) {
        errors.add('Backup record ${i + 1}: ${_message(error)}');
      }
    }
    return _preview(
      records,
      errors,
      source: 'CIDR Atlas JSON backup',
      existingRecords: existingRecords,
      warnings: [
        'This is a merged snapshot; absent existing records will be retained.',
      ],
    );
  }

  static ImportPreview _oci(Map<String, dynamic> root, String domain,
      List<PrefixRecord> existingRecords) {
    final records = <PrefixRecord>[];
    final errors = <String>[];
    final warnings = <String>[
      'OCI import coverage may be incomplete; missing resources will never be deleted or retired.',
    ];
    final metadataValue = root['metadata'];
    if (metadataValue != null && metadataValue is! Map) {
      throw const FormatException('OCI metadata must be an object.');
    }
    final metadata = metadataValue is Map
        ? Map<String, dynamic>.from(metadataValue)
        : <String, dynamic>{};
    final coverage = metadata['coverage'];
    if (coverage != null) warnings.add('Reported coverage: $coverage.');
    final collectedAt = _value(metadata, ['collectedAt', 'collected-at']);
    final verifiedAt =
        collectedAt.isEmpty ? null : DateTime.tryParse(collectedAt)?.toUtc();
    if (collectedAt.isNotEmpty && verifiedAt == null) {
      throw const FormatException(
          'metadata.collectedAt must be an ISO 8601 timestamp.');
    }
    if (verifiedAt == null) {
      warnings.add(
          'Source snapshot observation time is unknown; the audit timestamp records local import time only.');
    } else {
      warnings
          .add('Source snapshot observed at ${verifiedAt.toIso8601String()}.');
    }
    final vcnValues = <dynamic>[];
    final subnetValues = <dynamic>[];
    if (root.containsKey('vcns') || root.containsKey('subnets')) {
      if (root.containsKey('vcns'))
        vcnValues.addAll(_collection(root['vcns'], 'vcns'));
      if (root.containsKey('subnets'))
        subnetValues.addAll(_collection(root['subnets'], 'subnets'));
    } else if (root.containsKey('data')) {
      for (final value in _collection(root, 'data')) {
        if (value is Map &&
            (value.containsKey('vcn-id') || value.containsKey('vcnId'))) {
          subnetValues.add(value);
        } else {
          vcnValues.add(value);
        }
      }
    } else {
      throw const FormatException(
        'Expected an OCI CLI {"data": [...]} collection or a {"vcns": [...], "subnets": [...]} bundle.',
      );
    }
    for (final pair in [
      (PrefixKind.vcn, vcnValues),
      (PrefixKind.subnet, subnetValues),
    ]) {
      for (var index = 0; index < pair.$2.length; index++) {
        try {
          final value = pair.$2[index];
          if (value is! Map)
            throw const FormatException('Resource must be an object.');
          final item = Map<String, dynamic>.from(value);
          final id = _value(item, ['id']);
          if (id.isEmpty)
            throw const FormatException('Resource id is required.');
          final name = _value(item, ['display-name', 'displayName', 'name']);
          final cidrs = _ociCidrs(item);
          if (cidrs.isEmpty)
            throw const FormatException(
              'Resource has no IPv4 or IPv6 CIDR blocks.',
            );
          final vcnId = _value(item, ['vcn-id', 'vcnId']);
          if (pair.$1 == PrefixKind.subnet && vcnId.isEmpty)
            throw const FormatException('Subnet vcn-id is required.');
          final tenancy = _value(
            item,
            ['tenancy-id', 'tenancyId', 'tenancy'],
            fallback: _value(metadata, ['tenancy', 'tenancy-id', 'tenancyId']),
          );
          final region = _value(
              item,
              [
                'region',
              ],
              fallback: _value(metadata, ['region']));
          if (tenancy.isEmpty || region.isEmpty) {
            final warning =
                'Some OCI resources have unknown tenancy or region; supply bundle metadata to make import coverage explicit.';
            if (!warnings.contains(warning)) warnings.add(warning);
          }
          for (final cidr in cidrs) {
            final parsed = Cidr.parse(cidr);
            var parentId = '';
            if (pair.$1 == PrefixKind.subnet) {
              final parents = records
                  .where(
                    (record) =>
                        record.kind == PrefixKind.vcn &&
                        record.resourceId == vcnId &&
                        record.tenancy == tenancy &&
                        record.region == region,
                  )
                  .toList();
              final containing = parents
                  .where((record) => Cidr.parse(record.cidr).contains(parsed))
                  .toList();
              if (containing.isNotEmpty) {
                containing.sort(
                  (a, b) => Cidr.parse(b.cidr)
                      .prefixLength
                      .compareTo(Cidr.parse(a.cidr).prefixLength),
                );
                parentId = containing.first.id;
              } else if (parents.any(
                (record) => Cidr.parse(record.cidr).version == parsed.version,
              )) {
                throw FormatException(
                  'Subnet ${parsed.canonical} is outside bundled VCN $vcnId.',
                );
              }
            }
            final lifecycle = _value(item, [
              'lifecycle-state',
              'lifecycleState',
            ]);
            records.add(
              PrefixRecord(
                id: _stableId(
                    'oci', [domain, tenancy, region, id, parsed.canonical]),
                cidr: parsed.canonical,
                name: name.isEmpty ? id : name,
                routingDomain: domain,
                kind: pair.$1,
                status: lifecycle.toUpperCase() == 'TERMINATED'
                    ? PrefixStatus.retired
                    : PrefixStatus.active,
                tenancy: tenancy,
                region: region,
                compartment: _value(item, [
                  'compartment-id',
                  'compartmentId',
                  'compartment',
                ]),
                resourceId: id,
                vcnId: vcnId,
                parentId: parentId,
                source: 'oci',
                verifiedAt: verifiedAt,
              ),
            );
          }
        } catch (error) {
          errors.add('OCI ${pair.$1.name} ${index + 1}: ${_message(error)}');
        }
      }
    }
    final unlinkedSubnets = records
        .where(
          (record) =>
              record.kind == PrefixKind.subnet && record.parentId.isEmpty,
        )
        .length;
    if (unlinkedSubnets > 0)
      warnings.add(
        '$unlinkedSubnets subnet CIDRs have no VCN prefix in this import; their OCI vcn-id relationships are retained.',
      );
    return _preview(records, errors,
        source: 'OCI JSON',
        warnings: warnings,
        existingRecords: existingRecords);
  }

  static List<dynamic> _collection(dynamic value, String label) {
    if (value is List) return value;
    if (value is Map && value['data'] is List) return value['data'] as List;
    throw FormatException(
      'OCI $label must be an array or a CLI data collection.',
    );
  }

  static List<String> _ociCidrs(Map<String, dynamic> item) {
    final values = <String>{};
    for (final key in [
      'cidr-blocks',
      'cidrBlocks',
      'cidr-block',
      'cidrBlock',
      'ipv6-cidr-blocks',
      'ipv6CidrBlocks',
      'ipv6-cidr-block',
      'ipv6CidrBlock',
      'ipv6-private-cidr-blocks',
      'ipv6PrivateCidrBlocks',
    ]) {
      final value = item[key];
      if (value == null) continue;
      if (value is List) {
        for (final cidr in value) {
          if (cidr is! String)
            throw FormatException('$key must contain only CIDR strings.');
          if (cidr.trim().isNotEmpty) values.add(cidr.trim());
        }
      } else if (value is String) {
        if (value.trim().isNotEmpty) values.add(value.trim());
      } else {
        throw FormatException('$key must be a CIDR string or array.');
      }
    }
    return values.toList();
  }

  static PrefixRecord _record(
    Map<String, dynamic> fields, {
    required String origin,
  }) {
    for (final entry in fields.entries) {
      if (!columns.contains(entry.key))
        throw FormatException('Unknown record field "${entry.key}".');
      if (entry.value != null && entry.value is! String)
        throw FormatException('${entry.key} must be a string.');
    }
    final cidr = Cidr.parse(_string(fields, 'cidr')).canonical;
    final domain = _string(fields, 'routingDomain');
    final name = _string(fields, 'name');
    if (domain.isEmpty)
      throw const FormatException('routingDomain cannot be blank.');
    if (name.isEmpty) throw const FormatException('name cannot be blank.');
    final kindName = _string(fields, 'kind', fallback: 'vcn');
    final statusName = _string(fields, 'status', fallback: 'reserved');
    final kind =
        PrefixKind.values.where((value) => value.name == kindName).firstOrNull;
    final status = PrefixStatus.values
        .where((value) => value.name == statusName)
        .firstOrNull;
    if (kind == null) throw FormatException('Unknown kind "$kindName".');
    if (status == null) throw FormatException('Unknown status "$statusName".');
    final verified = _string(fields, 'verifiedAt');
    final verifiedAt = verified.isEmpty ? null : DateTime.tryParse(verified);
    if (verified.isNotEmpty && verifiedAt == null)
      throw const FormatException('verifiedAt must be an ISO 8601 timestamp.');
    final resourceId = _string(fields, 'resourceId');
    final id = _string(fields, 'id');
    if (origin == 'backup' && id.isEmpty)
      throw const FormatException('Backup record id cannot be blank.');
    return PrefixRecord(
      id: id.isEmpty
          ? _stableId('csv', [domain, kindName, resourceId, cidr])
          : id,
      cidr: cidr,
      name: name,
      routingDomain: domain,
      kind: kind,
      status: status,
      customer: _string(fields, 'customer'),
      tenancy: _string(fields, 'tenancy'),
      region: _string(fields, 'region'),
      compartment: _string(fields, 'compartment'),
      environment: _string(fields, 'environment'),
      owner: _string(fields, 'owner'),
      resourceId: resourceId,
      vcnId: _string(fields, 'vcnId'),
      parentId: _string(fields, 'parentId'),
      notes: fields['notes'] as String? ?? '',
      source:
          _string(fields, 'source', fallback: origin == 'backup' ? '' : origin),
      verifiedAt: verifiedAt,
    );
  }

  static ImportPreview _preview(
    List<PrefixRecord> records,
    List<String> errors, {
    required String source,
    List<String> warnings = const [],
    List<PrefixRecord> existingRecords = const [],
  }) {
    final incomingIds = records.map((record) => record.id).toSet();
    final combined = [
      ...existingRecords.where((record) => !incomingIds.contains(record.id)),
      ...records
    ];
    final completeErrors = [...errors, ...InventoryRules.validate(combined)];
    final completeWarnings = [...warnings];
    if (records.isEmpty && completeErrors.isEmpty)
      completeErrors.add('Import contains no prefix records.');
    if (completeErrors.isEmpty) {
      // Store reconciliation can fold imported OCI ids into existing manual
      // ids. Count parser warnings only within the incoming batch; callers
      // inspect mergedImportRecords for the authoritative resulting conflicts.
      final conflicts = InventoryRules.conflicts(records);
      if (conflicts.isNotEmpty)
        completeWarnings.add(
          '${conflicts.length} routing-domain conflict(s) will remain visible for review.',
        );
    }
    return ImportPreview(
      records: records,
      errors: completeErrors,
      warnings: completeWarnings,
      source: source,
    );
  }

  static String _stableId(String source, List<String> identity) =>
      '$source:${base64Url.encode(utf8.encode(jsonEncode(identity))).replaceAll('=', '')}';
  static String _header(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  static String _string(
    Map<String, dynamic> fields,
    String key, {
    String fallback = '',
  }) {
    final value = fields[key];
    if (value == null || value == '') return fallback;
    if (value is! String) throw FormatException('$key must be a string.');
    return value.trim();
  }

  static String _value(
    Map<String, dynamic> values,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      if (values[key] != null) return _string(values, key);
    }
    return fallback;
  }

  static String _message(Object error) =>
      error is FormatException ? error.message.toString() : error.toString();

  static String _lineEnding(String input) {
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      if (input[i] == '"') {
        if (quoted && i + 1 < input.length && input[i + 1] == '"') {
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && input[i] == '\r') {
        return i + 1 < input.length && input[i + 1] == '\n' ? '\r\n' : '\r';
      } else if (!quoted && input[i] == '\n') {
        return '\n';
      }
    }
    return '\n';
  }
}
