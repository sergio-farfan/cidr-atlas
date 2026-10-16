// CIDR Atlas
// Inventory editing, planning, and OCI import dialogs.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_oci/cidr_oci.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'oci_dialog.dart';
import 'help.dart';

String atlasLabel(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
String atlasError(Object error) =>
    error is FormatException ? error.message : '$error';

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.records,
    this.record,
    this.onSave,
  });
  final List<PrefixRecord> records;
  final PrefixRecord? record;

  /// Commits the reviewed record while the editor stays open. Returns `true`
  /// when the record was saved, so the editor closes with it, or `false` to
  /// keep editing. A thrown error is shown inline and the form input is kept.
  /// Without it, the editor returns the reviewed record unsaved.
  final Future<bool> Function(PrefixRecord record)? onSave;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late PrefixKind _kind;
  late PrefixStatus _status;
  late String _parent;
  String? _error;
  bool _saving = false;
  final _errorKey = GlobalKey();
  String? _advisoryParent;
  List<String> _advisories = const [];

  /// Non-blocking review notices for the edited record with the selected
  /// parent, recomputed only when the parent selection changes.
  List<String> _currentAdvisories() {
    final record = widget.record;
    if (record == null) return const [];
    if (_advisoryParent != _parent) {
      _advisoryParent = _parent;
      _advisories = InventoryRules.advisories(
        [
          ...widget.records.where((r) => r.id != record.id),
          record.copyWith(parentId: _parent),
        ],
        involving: {record.id},
      );
    }
    return _advisories;
  }

  /// Fields observed by OCI discovery. The next OCI refresh restores them, so
  /// they are read-only for records whose source is `oci`.
  static const _observedFields = {
    'name',
    'cidr',
    'routingDomain',
    'tenancy',
    'region',
    'compartment',
    'resourceId',
    'vcnId',
  };
  static const observedHelper =
      'Observed by OCI discovery; refresh from OCI to update.';
  bool get _observed => widget.record?.source == 'oci';
  @override
  void initState() {
    super.initState();
    final values = widget.record?.toJson() ?? <String, dynamic>{};
    _fields = {
      for (final key in [
        'name',
        'cidr',
        'routingDomain',
        'customer',
        'tenancy',
        'region',
        'compartment',
        'environment',
        'owner',
        'resourceId',
        'vcnId',
        'notes',
      ])
        key: TextEditingController(text: values[key] as String? ?? ''),
    };
    _kind = widget.record?.kind ?? PrefixKind.vcn;
    _status = widget.record?.status ?? PrefixStatus.reserved;
    _parent = widget.record?.parentId ?? '';
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    String? hint,
    String? helper,
    int lines = 1,
  }) {
    final readOnly = _observed && _observedFields.contains(key);
    return TextFormField(
      key: ValueKey('editor-$key'),
      controller: _fields[key],
      maxLines: lines,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: readOnly ? null : hint,
        helperText: readOnly ? observedHelper : helper,
        helperMaxLines: 3,
        suffixIcon: readOnly
            ? const Tooltip(
                message: observedHelper,
                child: Icon(Icons.lock_outline, size: 16),
              )
            : null,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return '$label is required';
        }
        if (key == 'cidr' && value != null && value.trim().isNotEmpty) {
          try {
            Cidr.parse(value.trim());
          } catch (error) {
            return atlasError(error);
          }
        }
        return null;
      },
    );
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    String value(String key) => _fields[key]!.text.trim();
    final original =
        widget.record ??
        PrefixRecord(
          id: 'manual:${DateTime.now().microsecondsSinceEpoch}',
          cidr: value('cidr'),
          name: value('name'),
          routingDomain: value('routingDomain'),
          source: 'manual',
        );
    final record = original.copyWith(
      cidr: Cidr.parse(value('cidr')).canonical,
      name: value('name'),
      routingDomain: value('routingDomain'),
      kind: _kind,
      status: _status,
      parentId: _parent,
      customer: value('customer'),
      tenancy: value('tenancy'),
      region: value('region'),
      compartment: value('compartment'),
      environment: value('environment'),
      owner: value('owner'),
      resourceId: value('resourceId'),
      vcnId: value('vcnId'),
      notes: value('notes'),
    );
    final errors = InventoryRules.validate([
      ...widget.records.where((r) => r.id != record.id),
      record,
    ]);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    final onSave = widget.onSave;
    if (onSave == null) {
      Navigator.pop(context, record);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await onSave(record);
      if (saved && mounted) Navigator.pop(context, record);
    } catch (error) {
      if (mounted) {
        setState(() => _error = atlasError(error));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final panel = _errorKey.currentContext;
          if (panel != null && panel.mounted) {
            Scrollable.ensureVisible(panel);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parents = widget.records
        .where((r) => r.id != widget.record?.id)
        .toList();
    return AlertDialog(
      title: Text(
        widget.record == null ||
                !widget.records.any((r) => r.id == widget.record!.id)
            ? 'New prefix'
            : 'Edit prefix',
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'One record per CIDR. Overlaps remain visible in Conflicts; hierarchy must be explicitly declared.',
                  style: TextStyle(color: Color(0xff98a6bc), fontSize: 13),
                ),
                if (_observed) ...[
                  const SizedBox(height: 14),
                  const MessagePanel(
                    message:
                        'OCI discovery observed this network. Its name, CIDR, '
                        'routing domain, kind and OCI identity are read-only '
                        'because the next OCI refresh restores them. Status, '
                        'parent, ownership and notes remain editable.',
                  ),
                ],
                for (final (index, advisory)
                    in _currentAdvisories().indexed) ...[
                  const SizedBox(height: 14),
                  MessagePanel(
                    key: ValueKey('editor-advisory-$index'),
                    message: 'Review notice (saving is not blocked): $advisory',
                  ),
                ],
                const SizedBox(height: 22),
                _field('name', 'Name', required: true, hint: 'Production VCN'),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        'cidr',
                        'Network CIDR',
                        required: true,
                        hint: '10.64.0.0/20',
                        helper: 'Enter the network address and /bits for a manual record. OCI imports supply their CIDRs automatically.',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _field(
                        'routingDomain',
                        'Routing domain',
                        required: true,
                        hint: 'corporate',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<PrefixKind>(
                        initialValue: _kind,
                        decoration: InputDecoration(
                          labelText: 'Kind',
                          helperText: _observed ? observedHelper : null,
                          helperMaxLines: 3,
                        ),
                        items: PrefixKind.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(
                                  v == PrefixKind.vcn
                                      ? 'VCN'
                                      : atlasLabel(v.name),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _observed
                            ? null
                            : (value) => setState(() => _kind = value!),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DropdownButtonFormField<PrefixStatus>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: PrefixStatus.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(atlasLabel(v.name)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _status = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: parents.any((r) => r.id == _parent)
                      ? _parent
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Declared parent',
                    helperText: 'Use the containing allocation or VCN; numeric containment alone is not a relationship.',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No declared parent'),
                    ),
                    ...parents.map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          '${r.cidr} · ${r.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _parent = value!),
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Ownership & OCI metadata',
                    style: TextStyle(fontSize: 14),
                  ),
                  children: [
                    for (final row in [
                      ['customer', 'Customer', 'owner', 'Owner'],
                      ['environment', 'Environment', 'region', 'Region'],
                      ['tenancy', 'Tenancy', 'compartment', 'Compartment'],
                      [
                        'resourceId',
                        'Resource OCID',
                        'vcnId',
                        'VCN OCID (for subnet)',
                      ],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Row(
                          children: [
                            Expanded(child: _field(row[0], row[1])),
                            const SizedBox(width: 14),
                            Expanded(child: _field(row[2], row[3])),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _field('notes', 'Notes', lines: 3),
                if (_error != null)
                  Padding(
                    key: _errorKey,
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: MessagePanel(message: _error!, error: true),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save prefix'),
        ),
      ],
    );
  }
}

class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.message,
    this.error = false,
    this.success = false,
  });
  final String message;
  final bool error;
  final bool success;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? const Color(0xffff8c8c)
        : success
        ? const Color(0xff77d8b4)
        : const Color(0xffe6c583);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error
                ? Icons.error_outline
                : success
                ? Icons.check_circle_outline
                : Icons.info_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class CheckerDialog extends StatefulWidget {
  const CheckerDialog({super.key, required this.records, this.domain});
  final List<PrefixRecord> records;
  final String? domain;
  @override
  State<CheckerDialog> createState() => _CheckerDialogState();
}

class _CheckerDialogState extends State<CheckerDialog> {
  final _cidr = TextEditingController();
  late final TextEditingController _domain;
  String _parent = '';
  PrefixKind _kind = PrefixKind.vcn;
  String? _result;
  bool _valid = false;
  @override
  void initState() {
    super.initState();
    _domain = TextEditingController(text: widget.domain ?? '');
  }

  @override
  void dispose() {
    _cidr.dispose();
    _domain.dispose();
    super.dispose();
  }

  void _invalidate() => setState(() {
    _result = null;
    _valid = false;
  });

  void _check() {
    try {
      final cidr = Cidr.parse(_cidr.text.trim());
      if (_domain.text.trim().isEmpty) {
        throw const FormatException('Enter an explicit routing domain.');
      }
      final candidate = PrefixRecord(
        id: '_check:${DateTime.now().microsecondsSinceEpoch}',
        cidr: cidr.canonical,
        name: 'Candidate prefix',
        routingDomain: _domain.text.trim(),
        kind: _kind,
        parentId: _parent,
      );
      final combined = [...widget.records, candidate];
      final errors = InventoryRules.validate(combined);
      if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
      final conflicts = InventoryRules.conflictsFor({candidate.id}, combined);
      setState(() {
        _valid = conflicts.isEmpty;
        _result = conflicts.isEmpty
            ? '${cidr.canonical} has no conflicts in ${candidate.routingDomain}.\nCheck external networks and incomplete import coverage before reserving.'
            : conflicts
                  .map((c) {
                    final other = c.first.id == candidate.id
                        ? c.second
                        : c.first;
                    return '${other.cidr} · ${other.name}\n${c.reason}';
                  })
                  .join('\n\n');
      });
    } catch (error) {
      setState(() {
        _valid = false;
        _result = atlasError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Can I use this CIDR?'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Compare a proposed prefix with the local register. Only prefixes in the same routing domain can conflict.',
              style: TextStyle(color: Color(0xff98a6bc), height: 1.5),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _cidr,
              onChanged: (_) => _invalidate(),
              decoration: const InputDecoration(
                labelText: 'CIDR',
                hintText: '10.64.32.0/20',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _domain,
              onChanged: (_) => _invalidate(),
              decoration: const InputDecoration(labelText: 'Routing domain'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PrefixKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Proposed kind'),
              items: PrefixKind.values
                  .map(
                    (k) => DropdownMenuItem(
                      value: k,
                      child: Text(
                        k == PrefixKind.vcn ? 'VCN' : atlasLabel(k.name),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _kind = v!;
                _result = null;
                _valid = false;
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _parent,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Declared parent (optional)',
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('No declared parent'),
                ),
                ...widget.records.map(
                  (r) => DropdownMenuItem(
                    value: r.id,
                    child: Text(
                      '${r.cidr} · ${r.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _parent = v!;
                _result = null;
                _valid = false;
              }),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: MessagePanel(
                  message: _result!,
                  error: !_valid,
                  success: _valid,
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(onPressed: _check, child: const Text('Check CIDR')),
    ],
  );
}

class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.existing,
    this.domain,
    this.proposedRecords,
    this.ociClient,
    this.ociClientFactory,
  });
  final List<PrefixRecord> existing;
  final String? domain;
  final List<PrefixRecord> Function(ImportPreview)? proposedRecords;
  final OciInventoryClient? ociClient;

  /// Creates OCI clients for discovery, including one bounded by an entered
  /// collection time limit; see [OciDiscoveryDialog.clientFactory].
  final OciClientFactory? ociClientFactory;
  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  late final TextEditingController _domain;
  String? _text;
  String? _filename;
  bool _csv = false;
  String? _fileError;
  ImportPreview? _preview;
  List<String> _combinedErrors = [];
  int _combinedConflicts = 0;
  List<String> _ociWarnings = [];
  bool _liveDiscovery = false;
  @override
  void initState() {
    super.initState();
    _domain = TextEditingController(text: widget.domain ?? '');
  }

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'CIDR inventories',
            extensions: ['csv', 'json'],
            uniformTypeIdentifiers: [
              'public.comma-separated-values-text',
              'public.json',
            ],
          ),
        ],
      );
      if (file == null) return;
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _text = content;
        _filename = file.name;
        _csv = file.name.toLowerCase().endsWith('.csv');
        _fileError = null;
        _ociWarnings = [];
        _liveDiscovery = false;
      });
      _parse();
    } catch (error) {
      if (mounted) {
        setState(() {
          _fileError = atlasError(error);
          _preview = null;
          _text = null;
          _combinedErrors = [];
          _combinedConflicts = 0;
        });
      }
    }
  }

  void _parse() {
    if (_text == null) return;
    final preview = _csv
        ? InventoryImport.csv(_text!, existingRecords: widget.existing)
        : InventoryImport.json(
            _text!,
            routingDomain: _domain.text,
            existingRecords: widget.existing,
          );
    if (!preview.canApply) {
      setState(() {
        _preview = preview;
        _combinedErrors = [];
        _combinedConflicts = 0;
      });
      return;
    }
    try {
      final merged =
          widget.proposedRecords?.call(preview) ??
          {
            for (final r in widget.existing) r.id: r,
            for (final r in preview.records) r.id: r,
          }.values.toList();
      final errors = preview.errors.isEmpty
          ? InventoryRules.validate(merged)
          : <String>[];
      setState(() {
        _preview = preview;
        _combinedErrors = errors;
        _combinedConflicts = errors.isEmpty
            ? InventoryRules.conflicts(merged).length
            : 0;
      });
    } catch (error) {
      setState(() {
        _preview = preview;
        _combinedErrors = [atlasError(error)];
        _combinedConflicts = 0;
      });
    }
  }

  Future<void> _discoverOci() async {
    setState(() {
      _preview = null;
      _text = null;
      _filename = null;
      _fileError = null;
      _ociWarnings = [];
      _liveDiscovery = false;
      _combinedErrors = [];
      _combinedConflicts = 0;
    });
    final selection = await showDialog<OciImportSelection>(
      context: context,
      builder: (_) => OciDiscoveryDialog(
        client: widget.ociClient,
        clientFactory: widget.ociClientFactory,
        domain: _domain.text,
      ),
    );
    if (!mounted || selection == null) return;
    setState(() {
      _text = selection.bundleJson;
      _csv = false;
      _filename = 'OCI CLI discovery';
      _domain.text = selection.routingDomain;
      _ociWarnings = selection.warnings;
      _liveDiscovery = true;
    });
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final emptyDiscovery = _liveDiscovery && preview?.isEmptyResult == true;
    final warnings = {..._ociWarnings, ...?preview?.warnings};
    final detailWarnings = warnings
        .where(
          (warning) =>
              warning.startsWith('Reported coverage:') ||
              warning.startsWith('Source snapshot observed at'),
        )
        .toList();
    return AlertDialog(
      title: const Text('Import inventory'),
      content: SizedBox(
        width: 740,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 580),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preview a CSV, CIDR Atlas JSON backup, or OCI inventory before saving. OCI discovery reads existing network CIDRs automatically; no manual CIDR is needed here. Existing records absent from the import are retained.',
                  style: TextStyle(color: Color(0xff98a6bc), height: 1.5),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _choose,
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text('Choose CSV or JSON'),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _filename ?? 'No file selected',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xff98a6bc)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: _discoverOci,
                  child: const Text('Discover from OCI CLI'),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _domain,
                  onChanged: (_) => _parse(),
                  decoration: const InputDecoration(
                    labelText: 'Routing domain for OCI imports',
                    hintText: 'corporate',
                    helperText: 'CSV and Atlas backups retain their own routing domains.',
                  ),
                ),
                if (_fileError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: MessagePanel(message: _fileError!, error: true),
                  ),
                if (preview != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    '${preview.records.length} network CIDR${preview.records.length == 1 ? '' : 's'} · ${preview.source}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (emptyDiscovery) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Discovery completed — no networks found',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const MessagePanel(
                      message: 'No manual CIDR is needed for OCI discovery. There is nothing to save. Review the profile, resource regions, selected scope and IAM permissions. For a direct compartment, networks may be in a child; enable all compartments or select that child. If all compartments are included, check permissions and region subscriptions.',
                    ),
                    TextButton.icon(
                      onPressed: _discoverOci,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Review discovery scope'),
                    ),
                  ],
                  if (!emptyDiscovery &&
                      (preview.errors.isNotEmpty || _combinedErrors.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: MessagePanel(
                        message: {
                          for (final error in preview.errors)
                            error == ImportPreview.emptyRecordsMessage
                                ? 'The selected file contains no network CIDR records. Choose a populated CSV or JSON inventory.'
                                : error,
                          ..._combinedErrors,
                        }.join('\n'),
                        error: true,
                      ),
                    ),
                  for (final warning in warnings.where(
                    (warning) => !detailWarnings.contains(warning),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: MessagePanel(message: warning),
                    ),
                  if (detailWarnings.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Coverage and observation details'),
                      children: [
                        for (final warning in detailWarnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: MessagePanel(message: warning),
                          ),
                      ],
                    ),
                  if (_combinedConflicts > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: MessagePanel(
                        message:
                            'The resulting inventory has $_combinedConflicts routing conflict(s). They will remain visible for review.',
                      ),
                    ),
                  if (preview.records.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(
                        children: [
                          for (final record in preview.records.take(30))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 165,
                                    child: Text(
                                      record.cidr,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      record.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    record.routingDomain,
                                    style: const TextStyle(
                                      color: Color(0xff98a6bc),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (preview.records.length > 30)
                            Text(
                              '…and ${preview.records.length - 30} more prefixes',
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('import-help'),
          onPressed: () => showAtlasHelp(context, topic: HelpTopic.imports),
          icon: const Icon(Icons.help_outline, size: 18),
          label: const Text('Import help'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              preview != null && preview.canApply && _combinedErrors.isEmpty
              ? () => Navigator.pop(context, preview)
              : null,
          child: const Text('Apply import'),
        ),
      ],
    );
  }
}

Future<void> exportInventory(
  BuildContext context,
  List<PrefixRecord> records, {
  required bool csv,
}) async {
  final extension = csv ? 'csv' : 'json';
  final destination = await getSaveLocation(
    suggestedName: 'cidr-atlas-inventory.$extension',
    acceptedTypeGroups: [
      XTypeGroup(
        label: csv ? 'CSV inventory' : 'JSON backup',
        extensions: [extension],
        uniformTypeIdentifiers: [
          csv ? 'public.comma-separated-values-text' : 'public.json',
        ],
      ),
    ],
  );
  if (destination == null) return;
  final content = csv
      ? InventoryImport.exportCsv(records)
      : InventoryImport.exportJson(records);
  final file = XFile.fromData(
    utf8.encode(content),
    mimeType: csv ? 'text/csv' : 'application/json',
    name: 'inventory.$extension',
  );
  await file.saveTo(destination.path);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Exported all ${records.length} prefixes to ${destination.path}',
        ),
      ),
    );
  }
}
