// CIDR Atlas
// Inventory import validation and export codecs.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:csv/csv.dart';

import 'identity.dart';

class ImportPreview {
  static const emptyRecordsMessage = 'Import contains no prefix records.';

  ImportPreview({
    required List<PrefixRecord> records,
    List<String> errors = const [],
    List<String> warnings = const [],
    required this.source,
    Set<String>? presentColumns,
  })  : records = List.unmodifiable(records),
        errors = List.unmodifiable(errors),
        warnings = List.unmodifiable(warnings),
        presentColumns =
            presentColumns == null ? null : Set.unmodifiable(presentColumns);

  final List<PrefixRecord> records;
  final List<String> errors;
  final List<String> warnings;
  final String source;

  /// The [InventoryImport.columns] the source actually supplied, or null when
  /// every record is complete. A CSV header with fewer columns sets this, so
  /// an update of an existing record changes only the supplied columns.
  final Set<String>? presentColumns;

  /// The record that results from applying [incoming] to the [existing]
  /// record with the same id in a non-OCI import. Columns the source did not
  /// supply keep their existing values, including status, kind, source and
  /// verifiedAt; their parser defaults apply only to new records. A supplied
  /// column replaces the existing value, even when its cell is blank.
  PrefixRecord mergeOnto(PrefixRecord existing, PrefixRecord incoming) {
    final present = presentColumns;
    if (present == null) return incoming;
    T pick<T>(String column, T current, T value) =>
        present.contains(column) ? value : current;
    return PrefixRecord(
      id: incoming.id,
      cidr: pick('cidr', existing.cidr, incoming.cidr),
      name: pick('name', existing.name, incoming.name),
      routingDomain:
          pick('routingDomain', existing.routingDomain, incoming.routingDomain),
      kind: pick('kind', existing.kind, incoming.kind),
      status: pick('status', existing.status, incoming.status),
      customer: pick('customer', existing.customer, incoming.customer),
      tenancy: pick('tenancy', existing.tenancy, incoming.tenancy),
      region: pick('region', existing.region, incoming.region),
      compartment:
          pick('compartment', existing.compartment, incoming.compartment),
      environment:
          pick('environment', existing.environment, incoming.environment),
      owner: pick('owner', existing.owner, incoming.owner),
      resourceId: pick('resourceId', existing.resourceId, incoming.resourceId),
      vcnId: pick('vcnId', existing.vcnId, incoming.vcnId),
      parentId: pick('parentId', existing.parentId, incoming.parentId),
      notes: pick('notes', existing.notes, incoming.notes),
      source: pick('source', existing.source, incoming.source),
      verifiedAt: pick('verifiedAt', existing.verifiedAt, incoming.verifiedAt),
    );
  }

  bool get canApply => records.isNotEmpty && errors.isEmpty;
  bool get isEmptyResult =>
      records.isEmpty && errors.every((error) => error == emptyRecordsMessage);
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
    final warnings = <String>[];
    var zonelessTimes = 0;
    Set<String>? presentColumns;
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
        if (!seen.contains(required)) {
          errors.add('Missing required CSV column "$required".');
        }
      }
      if (errors.isNotEmpty) {
        return ImportPreview(records: records, errors: errors, source: 'CSV');
      }
      presentColumns = seen;
      final existingById = {
        for (final record in existingRecords) record.id: record
      };
      // Rows without an id get an id derived from routing domain, kind,
      // resource id and CIDR, so re-importing the same file is idempotent.
      final generatedRows = <String, int>{};
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
          final value =
              _unescapeCell(cell < row.length ? row[cell].toString() : '');
          fields[headers[cell]] =
              headers[cell] == 'notes' ? value : value.trim();
        }
        final PrefixRecord record;
        try {
          record =
              _record(fields, origin: 'csv', zoneless: () => zonelessTimes++);
        } catch (error) {
          errors.add('CSV row ${index + 1}: ${_message(error)}');
          continue;
        }
        if ((fields['id'] as String? ?? '').isEmpty) {
          final earlier = generatedRows[record.id];
          if (earlier != null) {
            errors.add(
              'CSV rows $earlier and ${index + 1} describe the same cidr, kind, '
              'routingDomain and resourceId without an id; add an id column to '
              'import both.',
            );
            continue;
          }
          generatedRows[record.id] = index + 1;
          final existing = existingById[record.id];
          if (existing != null &&
              (existing.name != record.name ||
                  (seen.contains('customer') &&
                      existing.customer != record.customer))) {
            warnings.add(
              'CSV row ${index + 1} has no id and will replace existing record '
              '${existing.name} (${existing.cidr}, ${existing.routingDomain}) '
              'whose name or customer differs; add ids to keep both.',
            );
          }
        }
        records.add(record);
      }
    } catch (error) {
      errors.add(_message(error));
    }
    if (zonelessTimes > 0) warnings.add(_zonelessWarning(zonelessTimes));
    return _preview(records, errors,
        source: 'CSV',
        warnings: warnings,
        existingRecords: existingRecords,
        presentColumns: presentColumns);
  }

  static ImportPreview json(String input,
      {required String routingDomain,
      List<PrefixRecord> existingRecords = const []}) {
    try {
      final decoded = jsonDecode(input);
      if (decoded is! Map) {
        throw const FormatException('JSON root must be an object.');
      }
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
        [
          for (final value in _exportRow(record))
            _escapeCell(value?.toString() ?? '')
        ],
    ]);
  }

  static List<dynamic> _exportRow(PrefixRecord record) {
    final json = record.toJson();
    return [for (final column in columns) json[column]];
  }

  // Spreadsheet applications evaluate a cell that starts with one of these
  // characters as a formula. Leading quotes are counted too, so a value that
  // already starts with a quote survives the export and import round trip.
  static final _formulaCell = RegExp("^'*[=+\\-@\t\r]");

  /// Prefixes a quote to a cell a spreadsheet would read as a formula.
  static String _escapeCell(String value) =>
      _formulaCell.hasMatch(value) ? "'$value" : value;

  /// Removes exactly the quote that [_escapeCell] adds.
  static String _unescapeCell(String value) =>
      value.startsWith("'") && _formulaCell.hasMatch(value)
          ? value.substring(1)
          : value;

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
    if (values is! List) {
      throw const FormatException('Backup records must be an array.');
    }
    final records = <PrefixRecord>[];
    final errors = <String>[];
    var zonelessTimes = 0;
    for (var i = 0; i < values.length; i++) {
      try {
        if (values[i] is! Map) {
          throw const FormatException('Record must be an object.');
        }
        records.add(
          _record(
            Map<String, dynamic>.from(values[i] as Map),
            origin: 'backup',
            zoneless: () => zonelessTimes++,
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
        if (zonelessTimes > 0) _zonelessWarning(zonelessTimes),
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
      if (root.containsKey('vcns')) {
        vcnValues.addAll(_collection(root['vcns'], 'vcns'));
      }
      if (root.containsKey('subnets')) {
        subnetValues.addAll(_collection(root['subnets'], 'subnets'));
      }
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
    bool truncated(dynamic value) =>
        value is Map && value['opc-next-page'] != null;
    if (truncated(root) ||
        truncated(root['vcns']) ||
        truncated(root['subnets'])) {
      warnings.add(
        'Input is a single truncated OCI CLI page (opc-next-page present); '
        'rerun the list with --all. Unlisted ranges will appear free.',
      );
    }
    for (final pair in [
      (PrefixKind.vcn, vcnValues),
      (PrefixKind.subnet, subnetValues),
    ]) {
      for (var index = 0; index < pair.$2.length; index++) {
        try {
          final value = pair.$2[index];
          if (value is! Map) {
            throw const FormatException('Resource must be an object.');
          }
          final item = Map<String, dynamic>.from(value);
          final id = _value(item, ['id']);
          if (id.isEmpty) {
            throw const FormatException('Resource id is required.');
          }
          final name = _value(item, ['display-name', 'displayName', 'name']);
          final cidrs = _ociCidrs(item);
          if (cidrs.isEmpty) {
            throw const FormatException(
              'Resource has no IPv4 or IPv6 CIDR blocks.',
            );
          }
          final vcnId = _value(item, ['vcn-id', 'vcnId']);
          if (pair.$1 == PrefixKind.subnet && vcnId.isEmpty) {
            throw const FormatException('Subnet vcn-id is required.');
          }
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
    if (unlinkedSubnets > 0) {
      warnings.add(
        '$unlinkedSubnets subnet CIDRs have no VCN prefix in this import; their OCI vcn-id relationships are retained.',
      );
    }
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

  /// The resource's distinct CIDRs in canonical form, so equivalent spellings
  /// across alias keys describe one prefix. Invalid CIDRs throw.
  static List<String> _ociCidrs(Map<String, dynamic> item) {
    final values = <String>{};
    for (final key in [
      'cidr-blocks',
      'cidrBlocks',
      'cidr-block',
      'cidrBlock',
      'ipv4-cidr-blocks',
      'ipv4CidrBlocks',
      'ipv6-cidr-blocks',
      'ipv6CidrBlocks',
      'ipv6-cidr-block',
      'ipv6CidrBlock',
      'ipv6-private-cidr-blocks',
      'ipv6PrivateCidrBlocks',
      'byoipv6-cidr-blocks',
      'byoipv6CidrBlocks',
      'byoIpv6CidrBlocks',
    ]) {
      final value = item[key];
      if (value == null) continue;
      if (value is List) {
        for (final cidr in value) {
          if (cidr is! String) {
            throw FormatException('$key must contain only CIDR strings.');
          }
          if (cidr.trim().isNotEmpty) {
            values.add(Cidr.parse(cidr.trim()).canonical);
          }
        }
      } else if (value is String) {
        if (value.trim().isNotEmpty) {
          values.add(Cidr.parse(value.trim()).canonical);
        }
      } else {
        throw FormatException('$key must be a CIDR string or array.');
      }
    }
    return values.toList();
  }

  static PrefixRecord _record(
    Map<String, dynamic> fields, {
    required String origin,
    void Function()? zoneless,
  }) {
    for (final entry in fields.entries) {
      if (!columns.contains(entry.key)) {
        throw FormatException('Unknown record field "${entry.key}".');
      }
      if (entry.value != null && entry.value is! String) {
        throw FormatException('${entry.key} must be a string.');
      }
    }
    final cidr = Cidr.parse(_string(fields, 'cidr')).canonical;
    final domain = _string(fields, 'routingDomain');
    final name = _string(fields, 'name');
    if (domain.isEmpty) {
      throw const FormatException('routingDomain cannot be blank.');
    }
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
    DateTime? verifiedAt;
    if (verified.isNotEmpty) {
      try {
        verifiedAt = parseObservationTime(verified);
      } on FormatException catch (error) {
        // v0.3.0 wrote local times without a zone in backups and CSV
        // exports. Read that legacy form as local time, as v0.3.0 did and as
        // the store still does; calendar rollover and other forms stay
        // rejected with the strict message.
        final legacy = tryParseStoredTimestamp(verified);
        if (legacy == null || legacy.isUtc) {
          throw FormatException(
              'Invalid verifiedAt "$verified": ${error.message}');
        }
        verifiedAt = legacy.toUtc();
        zoneless?.call();
      }
    }
    final resourceId = _string(fields, 'resourceId');
    final id = _string(fields, 'id');
    if (origin == 'backup' && id.isEmpty) {
      throw const FormatException('Backup record id cannot be blank.');
    }
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
    Set<String>? presentColumns,
  }) {
    final incomingIds = records.map((record) => record.id).toSet();
    final existingById = {
      for (final record in existingRecords) record.id: record
    };
    // Validate partial-column updates as the store will apply them.
    final merging = ImportPreview(
      records: const [],
      source: source,
      presentColumns: presentColumns,
    );
    final combined = [
      ...existingRecords.where((record) => !incomingIds.contains(record.id)),
      for (final record in records)
        existingById[record.id] == null
            ? record
            : merging.mergeOnto(existingById[record.id]!, record),
    ];
    final completeErrors = [...errors, ...InventoryRules.validate(combined)];
    final completeWarnings = [...warnings];
    if (records.isEmpty && completeErrors.isEmpty) {
      completeErrors.add(ImportPreview.emptyRecordsMessage);
    }
    if (completeErrors.isEmpty) {
      // Store reconciliation can fold imported OCI ids into existing manual
      // ids. Count parser warnings only within the incoming batch; callers
      // inspect mergedImportRecords for the authoritative resulting conflicts.
      final conflicts = InventoryRules.conflicts(records);
      if (conflicts.isNotEmpty) {
        completeWarnings.add(
          '${conflicts.length} routing-domain conflict(s) will remain visible for review.',
        );
      }
      if (source == 'OCI JSON') {
        completeWarnings.addAll(_observationWarnings(records, existingRecords));
      }
      // Non-blocking review notices for the combined inventory, such as a
      // subnet still parented by a placeholder VCN after its real VCN is
      // recorded. They never prevent the import.
      for (final advisory in InventoryRules.advisories(combined)) {
        if (!completeWarnings.contains(advisory)) {
          completeWarnings.add(advisory);
        }
      }
    }
    return ImportPreview(
      records: records,
      errors: completeErrors,
      warnings: completeWarnings,
      source: source,
      presentColumns: presentColumns,
    );
  }

  /// Reconciliation notices for OCI observations of existing records, matched
  /// as the store matches them: by natural OCI identity, otherwise by id. The
  /// merge itself is unchanged; these notices make its effects reviewable.
  static List<String> _observationWarnings(
    List<PrefixRecord> records,
    List<PrefixRecord> existingRecords,
  ) {
    if (existingRecords.isEmpty) return const [];
    final existingById = {
      for (final record in existingRecords) record.id: record
    };
    final retired = <PrefixRecord>[];
    final newer = <(PrefixRecord, DateTime, DateTime)>[];
    for (final incoming in records) {
      if (incoming.source != 'oci') continue;
      final matches = existingRecords
          .where((existing) => sameOciIdentity(existing, incoming))
          .toList();
      if (matches.length > 1) continue;
      final existing =
          matches.isEmpty ? existingById[incoming.id] : matches.single;
      if (existing == null) continue;
      if (existing.status == PrefixStatus.retired &&
          incoming.status != PrefixStatus.retired) {
        retired.add(existing);
      }
      final observed = incoming.verifiedAt;
      final known = existing.verifiedAt;
      if (observed != null && known != null && observed.isBefore(known)) {
        newer.add((existing, known, observed));
      }
    }
    String examples(Iterable<String> values) {
      final list = values.toList();
      const shown = 3;
      return [
        ...list.take(shown),
        if (list.length > shown) 'and ${list.length - shown} more',
      ].join(', ');
    }

    return [
      if (retired.isNotEmpty)
        '${retired.length} record${retired.length == 1 ? ' is' : 's are'} '
            'marked retired but still observed live by OCI (e.g. '
            '${examples(retired.map((record) => '${record.name} (${record.cidr})'))}); '
            'they stay retired, so their space is treated as free.',
      if (newer.isNotEmpty)
        '${newer.length} record${newer.length == 1 ? ' has' : 's have'} a '
            'newer observation than this bundle (e.g. '
            '${examples(newer.map((item) => '${item.$1.name} (${item.$1.cidr}) observed at ${item.$2.toUtc().toIso8601String()}'))}); '
            'applying rolls their observed fields and verifiedAt back to '
            '${newer.first.$3.toUtc().toIso8601String()}.',
    ];
  }

  static String _zonelessWarning(int count) => count == 1
      ? '1 verifiedAt value has no UTC offset and was read as local time.'
      : '$count verifiedAt values have no UTC offset and were read as local '
          'time.';

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
