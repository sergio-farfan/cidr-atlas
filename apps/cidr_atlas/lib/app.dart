// CIDR Atlas
// Desktop inventory workspace and navigation.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_oci/cidr_oci.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'controller.dart';
import 'cidr_inspector.dart';
import 'dialogs.dart';
import 'help.dart';
import 'oci_dialog.dart';
import 'settings.dart';
import 'theme.dart';
import 'visual_planner.dart';

/// Channel for native macOS menu commands sent by `AppDelegate.swift`.
const atlasMenuChannel = MethodChannel('dev.cidratlas.desktop/menu');

class AtlasApp extends StatefulWidget {
  const AtlasApp({
    super.key,
    required this.controller,
    this.appearance,
    this.ociClient,
    this.ociClientFactory,
  });
  final AtlasController controller;

  /// The appearance preference. Production loads it from user defaults;
  /// without one the app follows macOS and keeps changes in memory only.
  final AppearanceController? appearance;

  /// OCI adapter for discovery; defaults to the installed OCI CLI.
  final OciInventoryClient? ociClient;

  /// Creates OCI adapters, including one bounded by an entered collection
  /// time limit. Production passes [OciDiscoveryDialog.defaultClientFactory].
  final OciClientFactory? ociClientFactory;

  @override
  State<AtlasApp> createState() => _AtlasAppState();
}

class _AtlasAppState extends State<AtlasApp> {
  AppearanceController? _fallbackAppearance;

  AppearanceController get _appearance =>
      widget.appearance ?? (_fallbackAppearance ??= AppearanceController());

  @override
  void dispose() {
    _fallbackAppearance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _appearance,
    builder: (context, _) => MaterialApp(
      title: 'CIDR Atlas',
      debugShowCheckedModeBanner: false,
      theme: atlasTheme(Brightness.light),
      darkTheme: atlasTheme(Brightness.dark),
      themeMode: _appearance.themeMode,
      home: _Workspace(
        controller: widget.controller,
        appearance: _appearance,
        ociClient: widget.ociClient,
        ociClientFactory: widget.ociClientFactory,
      ),
    ),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({
    required this.controller,
    required this.appearance,
    this.ociClient,
    this.ociClientFactory,
  });
  final AtlasController controller;
  final AppearanceController appearance;
  final OciInventoryClient? ociClient;
  final OciClientFactory? ociClientFactory;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  AtlasController get c => widget.controller;
  AtlasPalette get p => context.palette;
  bool _tree = false;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    atlasMenuChannel.setMethodCallHandler(_onMenuCall);
  }

  @override
  void dispose() {
    atlasMenuChannel.setMethodCallHandler(null);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Handles the native macOS menu: **CIDR Atlas > Settings…** (Cmd+,)
  /// reaches here when Flutter itself did not handle the shortcut.
  Future<void> _onMenuCall(MethodCall call) async {
    // Reply at once; the dialog stays open after the menu command returns.
    if (call.method == 'openSettings') unawaited(_openSettings());
  }

  /// Opens Settings once; a second request while it is open is ignored.
  Future<void> _openSettings() async {
    if (_settingsOpen || !mounted) return;
    _settingsOpen = true;
    try {
      await showAtlasSettings(context, widget.appearance);
    } finally {
      _settingsOpen = false;
    }
  }

  Future<void> _editor([PrefixRecord? record]) => showDialog<PrefixRecord>(
    context: context,
    builder: (_) =>
        RecordEditor(records: c.records, record: record, onSave: _saveEdited),
  );

  /// Saves an edited record while its editor stays open, so a conflict
  /// cancellation or store failure keeps the user's input.
  Future<bool> _saveEdited(PrefixRecord result) async {
    final combined = [
      ...c.store.list().where((r) => r.id != result.id),
      result,
    ];
    final conflicts = InventoryRules.conflictsFor({result.id}, combined);
    var confirmedConflicts = false;
    if (conflicts.isNotEmpty) {
      if (!mounted) return false;
      confirmedConflicts =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('This prefix has routing conflicts'),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Review the overlapping ranges below. You can save an observed conflict deliberately so it remains visible in the register.',
                      ),
                      const SizedBox(height: 18),
                      for (final conflict in conflicts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: MessagePanel(
                            message:
                                '${conflict.first.cidr} · ${conflict.first.name}\n${conflict.second.cidr} · ${conflict.second.name}\n${conflict.reason}',
                            error: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save with conflicts'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmedConflicts) return false;
    }
    if (!mounted) return false;
    c.save(result, rejectConflicts: !confirmedConflicts);
    return true;
  }

  Future<void> _reserveRecommendation(PrefixRecord proposal) =>
      showDialog<PrefixRecord>(
        context: context,
        builder: (_) => RecordEditor(
          records: c.records,
          record: proposal,
          onSave: (reviewed) async {
            _reserveReviewed(proposal, reviewed);
            return true;
          },
        ),
      );

  /// Strictly reserves a reviewed planner proposal. Failures propagate to the
  /// still-open editor; this path never offers the manual conflict override.
  void _reserveReviewed(PrefixRecord proposal, PrefixRecord reviewed) {
    if (reviewed.id != proposal.id ||
        reviewed.cidr != proposal.cidr ||
        reviewed.routingDomain != proposal.routingDomain ||
        reviewed.parentId != proposal.parentId ||
        reviewed.kind != proposal.kind ||
        reviewed.tenancy != proposal.tenancy ||
        reviewed.region != proposal.region ||
        reviewed.resourceId != proposal.resourceId ||
        reviewed.vcnId != proposal.vcnId ||
        reviewed.status == PrefixStatus.retired) {
      throw const FormatException(
        'Recalculate the recommendation after changing its network, scope, '
        'parent, kind, or allocation state.',
      );
    }
    final notes = reviewed.notes.contains(proposal.notes)
        ? reviewed.notes
        : [
            reviewed.notes.trim(),
            proposal.notes,
          ].where((part) => part.isNotEmpty).join('\n\n');
    c.reserve(reviewed.copyWith(notes: notes, source: 'planner'));
  }

  void _guard(void Function() operation) {
    try {
      operation();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Could not complete the change'),
        content: SizedBox(width: 520, child: SelectableText(atlasError(error))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final result = await showDialog<ImportPreview>(
      context: context,
      builder: (_) => ImportDialog(
        existing: c.records,
        domain: c.domain,
        proposedRecords: c.store.mergedImportRecords,
        ociClient: widget.ociClient,
        ociClientFactory: widget.ociClientFactory,
      ),
    );
    if (result != null && mounted) {
      _guard(() => c.applyImport(result));
    }
  }

  Future<void> _export(bool csv) async {
    try {
      // The database is shared with cidrctl: back up what it holds now, not
      // the records loaded at the last refresh.
      c.refresh();
      await exportInventory(context, List.of(c.records), csv: csv);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _delete(PrefixRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete prefix?'),
        content: Text(
          'Remove ${record.cidr} · ${record.name} from this local register? Its change history will remain. Parent prefixes cannot be removed while children reference them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete prefix'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _guard(() => c.remove(record.id));
  }

  Future<void> _removeDemo() async {
    final count = c.records.where(AtlasController.isDemo).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove sample data?'),
        content: Text(
          'Delete the $count fictional sample record${count == 1 ? '' : 's'} '
          'from this local register in one change. Other records are kept. '
          'Records you added under a sample network must be removed or '
          're-parented first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove sample data'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _guard(c.removeDemo);
  }

  /// Deletes every local record, or one routing domain, after a typed
  /// confirmation. History is kept; nothing outside the database changes.
  Future<void> _clearInventory() async {
    // The database is shared with cidrctl: confirm what it holds now.
    try {
      c.refresh();
    } catch (error) {
      _showError(error);
      return;
    }
    if (c.records.isEmpty) return;
    final request = await showDialog<ClearInventoryRequest>(
      context: context,
      builder: (_) => ClearInventoryDialog(
        records: List.of(c.records),
        initialDomain: c.domain,
        onExportBackup: () => _export(false),
      ),
    );
    if (request == null || !mounted) return;
    _guard(() {
      c.clearInventory(
        routingDomain: request.routingDomain,
        expectedCount: request.count,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${request.count} local record'
            '${request.count == 1 ? '' : 's'}'
            '${request.routingDomain == null ? '' : ' in ${request.routingDomain}'}. '
            'Change history is kept.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
          _editor(),
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
        c.navigate(0);
        _searchFocus.requestFocus();
      },
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true): _import,
      const SingleActivator(LogicalKeyboardKey.comma, meta: true):
          _openSettings,
    },
    child: Focus(
      autofocus: true,
      child: AnimatedBuilder(
        animation: c,
        builder: (context, _) => Scaffold(
          body: Row(
            children: [
              _sidebar(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    Expanded(
                      child: switch (c.page) {
                        1 => _conflicts(),
                        2 => VisualPlanner(
                          records: c.records,
                          conflicts: c.conflicts,
                          onReserve: _reserveRecommendation,
                        ),
                        3 => _history(),
                        _ => _inventory(),
                      },
                    ),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: p.border)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 12,
                            color: p.textSecondary,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'LOCAL INVENTORY',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 10,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${c.records.length} prefixes  ·  ${c.domains.length} routing domains',
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sidebar() => Container(
    width: 202,
    decoration: BoxDecoration(
      color: p.sidebar,
      border: Border(right: BorderSide(color: p.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 34, 18, 34),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.brandTile,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.hub_outlined,
                  color: p.accentStrong,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CIDR Atlas',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -.5,
                      ),
                    ),
                    Text(
                      'NETWORK WORKSPACE',
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 8,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 24, bottom: 14),
          child: Text(
            'WORKSPACE',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 10,
              letterSpacing: 1.6,
            ),
          ),
        ),
        for (final item in [
          (Icons.grid_view_rounded, 'Inventory'),
          (Icons.shield_outlined, 'Conflicts'),
          (Icons.account_tree_outlined, 'Planner'),
          (Icons.history_rounded, 'History'),
        ].indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Material(
              color: c.page == item.$1 ? p.navSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => c.navigate(item.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.$2.$1,
                        size: 19,
                        color: c.page == item.$1 ? p.accent : p.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.$2.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: c.page == item.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: c.page == item.$1
                                ? p.textSelected
                                : p.textSecondary,
                          ),
                        ),
                      ),
                      if (item.$1 == 1 && c.conflicts.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: p.conflictBadgeBackground,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '${c.conflicts.length}',
                            style: TextStyle(
                              fontSize: 10,
                              color: p.conflictBadgeText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.sidebarCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.desktop_mac_rounded, color: p.accent, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Local-first',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 9),
                Text(
                  'Your address plan, on this Mac. Import offline. Plan with confidence.',
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 18, 22),
          child: Text(
            'v0.4.0  ·  MACOS PREVIEW',
            style: TextStyle(
              color: p.textFaint,
              fontSize: 9,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _header() {
    const titles = [
      'Address inventory',
      'Routing conflicts',
      'Visual address planner',
      'Change history',
    ];
    const subtitles = [
      'A clear view of every network you own.',
      'Review overlapping ranges in connected address spaces.',
      'Right-size the next allocation and preserve useful address space.',
      'A local audit trail of inventory changes.',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 27, 26, 23),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[c.page],
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitles[c.page],
                  style: TextStyle(color: p.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('open-settings'),
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: Icon(
              Icons.settings_outlined,
              size: 20,
              color: p.textSecondary,
            ),
          ),
          IconButton(
            tooltip: 'Help and examples',
            onPressed: () => showAtlasHelp(context),
            icon: Icon(Icons.help_outline, size: 20, color: p.textSecondary),
          ),
          IconButton(
            tooltip: 'Refresh from local database',
            onPressed: () => _guard(c.refresh),
            icon: Icon(Icons.refresh_rounded, size: 20, color: p.textSecondary),
          ),
          const SizedBox(width: 5),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: const Text('Import', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 9),
          PopupMenuButton<bool>(
            tooltip: 'Export all inventory',
            onSelected: _export,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: false,
                child: Text('All inventory → JSON backup'),
              ),
              const PopupMenuItem(
                value: true,
                child: Text('All inventory → CSV'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                children: [
                  Icon(Icons.file_upload_outlined, size: 17),
                  SizedBox(width: 7),
                  Text('Export all', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 15),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),
          FilledButton.icon(
            onPressed: () => _editor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              'New prefix',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventory() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
        child: Row(
          children: [
            Expanded(
              child: _metric(
                'TOTAL PREFIXES',
                '${c.records.length}',
                Icons.lan_outlined,
                p.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metric(
                'ACTIVE',
                '${c.records.where((r) => r.status == PrefixStatus.active).length}',
                Icons.radio_button_checked,
                p.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metric(
                'PLANNED / RESERVED',
                '${c.records.where((r) => r.status == PrefixStatus.planned || r.status == PrefixStatus.reserved).length}',
                Icons.bookmark_border,
                p.reserved,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metric(
                'CONFLICTS',
                '${c.conflicts.length}',
                Icons.shield_outlined,
                c.conflicts.isEmpty ? p.success : p.danger,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 18),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: (value) => c.updateFilters(query: value),
                decoration: const InputDecoration(
                  hintText: 'Search CIDRs, names, owners…',
                  prefixIcon: Icon(Icons.search, size: 19),
                  suffixText: '⌘F',
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: ValueKey('domain-${c.domain}-${c.domains.length}'),
                initialValue: c.domain ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Routing domain'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All domains', style: TextStyle(fontSize: 12)),
                  ),
                  ...c.domains.map(
                    (d) => DropdownMenuItem(
                      value: d,
                      child: Text(
                        d,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
                onChanged: (v) =>
                    c.updateFilters(routingDomain: v, clearDomain: v == ''),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 132,
              child: DropdownButtonFormField<PrefixStatus?>(
                key: ValueKey('status-${c.status}'),
                initialValue: c.status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text(
                      'All statuses',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ...PrefixStatus.values.map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        atlasLabel(s.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
                onChanged: (v) =>
                    c.updateFilters(state: v, clearStatus: v == null),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Can I use this CIDR?',
              child: IconButton.filledTonal(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      CheckerDialog(records: c.records, domain: c.domain),
                ),
                icon: const Icon(Icons.rule_rounded, size: 21),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: c.records.isEmpty
            ? _emptyInventory()
            : LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _inventoryTable()),
                    if (constraints.maxWidth >= 1000 && c.selected != null)
                      SizedBox(width: 290, child: _details(c.selected!)),
                  ],
                ),
              ),
      ),
    ],
  );

  Widget _metric(String title, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      color: p.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 13),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 28,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _emptyInventory() => Center(
    child: SingleChildScrollView(
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: p.emptyTile,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.account_tree_outlined,
                size: 38,
                color: p.accent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Build your address map',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Import an OCI inventory or reserve your first prefix. Keep allocations, VCNs, and subnets together in one place.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                height: 1.7,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 25),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_download_outlined, size: 17),
                  label: const Text('Import inventory'),
                ),
                OutlinedButton(
                  onPressed: () => _editor(),
                  child: const Text('Add a prefix'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TextButton(
              onPressed: () => _guard(c.loadDemo),
              child: Text(
                'Explore with fictional sample data',
                style: TextStyle(color: p.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _inventoryTable() {
    final records = c.filtered;
    return Container(
      margin: const EdgeInsets.fromLTRB(26, 0, 26, 24),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
            child: Row(
              children: [
                Text(
                  '${records.length} prefixes',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Select a row to inspect',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(color: p.textSecondary, fontSize: 11),
                  ),
                ),
                if (c.hasDemoRecords)
                  TextButton.icon(
                    key: const ValueKey('remove-sample-data'),
                    onPressed: _removeDemo,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: const Text(
                      'Remove sample data',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('clear-inventory'),
                  tooltip: 'Clear inventory…',
                  visualDensity: VisualDensity.compact,
                  onPressed: c.records.isEmpty ? null : _clearInventory,
                  icon: Icon(
                    Icons.delete_forever_outlined,
                    size: 18,
                    color: p.textSecondary,
                  ),
                ),
                Tooltip(
                  message: _tree ? 'Flat list' : 'Hierarchy view',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _tree = !_tree),
                    icon: Icon(
                      _tree
                          ? Icons.table_rows_outlined
                          : Icons.account_tree_outlined,
                      size: 18,
                      color: p.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(
                      'No prefixes match your filters.',
                      style: TextStyle(color: p.textSecondary),
                    ),
                  )
                : _tree
                // Tiles paint their ink on this transparent Material rather
                // than behind the table's coloured box.
                ? Material(
                    type: MaterialType.transparency,
                    child: ListView(children: _hierarchy(records)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < 700
                            ? 700
                            : constraints.maxWidth,
                        child: Column(
                          children: [
                            _tableHeader(),
                            Expanded(
                              child: ListView.builder(
                                itemCount: records.length,
                                itemBuilder: (_, index) =>
                                    _tableRow(records[index]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() => Container(
    height: 36,
    color: p.tableHeader,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        SizedBox(
          width: 164,
          child: Text(
            'PREFIX / KIND',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            'NAME',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'ROUTING DOMAIN',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(
          width: 108,
          child: Text(
            'REGION',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(
          width: 87,
          child: Text(
            'STATUS',
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(width: 28),
      ],
    ),
  );

  void _inspect(PrefixRecord record) {
    c.select(record.id);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 400,
          height: 640,
          child: AnimatedBuilder(
            animation: c,
            builder: (context, child) {
              final current = c.records
                  .where((r) => r.id == record.id)
                  .firstOrNull;
              if (current != null) return _details(current);
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('This prefix has been removed.'),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _tableRow(PrefixRecord record) => Material(
    color: c.selectedId == record.id ? p.rowSelected : Colors.transparent,
    child: InkWell(
      onTap: () {
        c.select(record.id);
        if (MediaQuery.sizeOf(context).width < 1202) {
          _inspect(record);
        }
      },
      onDoubleTap: () => _editor(record),
      child: Container(
        height: 67,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.rowDivider)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 164,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.cidr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    record.kind == PrefixKind.vcn
                        ? 'VCN'
                        : atlasLabel(record.kind.name),
                    style: TextStyle(color: p.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (record.owner.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        record.owner,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.textSecondary, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  record.routingDomain,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                ),
              ),
            ),
            SizedBox(
              width: 108,
              child: Text(
                record.region.isEmpty ? '—' : record.region,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: p.textSecondary),
              ),
            ),
            SizedBox(
              width: 87,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(record.status),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: p.textSecondary),
          ],
        ),
      ),
    ),
  );

  List<Widget> _hierarchy(List<PrefixRecord> records) {
    final visible = records.map((r) => r.id).toSet();
    final childrenOf = <String, List<PrefixRecord>>{};
    for (final r in records) {
      if (r.parentId.isNotEmpty) (childrenOf[r.parentId] ??= []).add(r);
    }
    Widget branch(PrefixRecord record, Set<String> ancestors) {
      final children = [
        for (final child in childrenOf[record.id] ?? const <PrefixRecord>[])
          if (!ancestors.contains(child.id)) child,
      ];
      if (children.isEmpty) {
        return ListTile(
          dense: true,
          leading: Icon(
            record.kind == PrefixKind.subnet
                ? Icons.segment
                : Icons.lan_outlined,
            size: 18,
            color: p.accent,
          ),
          title: Text(
            '${record.cidr}  ·  ${record.name}',
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            record.routingDomain,
            style: const TextStyle(fontSize: 10),
          ),
          trailing: _statusBadge(record.status),
          onTap: () => _inspect(record),
        );
      }
      return ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.folder_outlined, size: 18, color: p.accent),
        title: Text(
          '${record.cidr}  ·  ${record.name}',
          style: const TextStyle(fontSize: 12),
        ),
        subtitle: Text(
          record.routingDomain,
          style: const TextStyle(fontSize: 10),
        ),
        trailing: IconButton(
          tooltip: 'Inspect prefix',
          onPressed: () => _inspect(record),
          icon: Icon(Icons.info_outline, size: 18, color: p.accent),
        ),
        childrenPadding: const EdgeInsets.only(left: 20),
        children: [
          for (final child in children)
            branch(child, {...ancestors, record.id}),
        ],
      );
    }

    return records
        .where((r) => r.parentId.isEmpty || !visible.contains(r.parentId))
        .map((r) => branch(r, {r.id}))
        .toList();
  }

  Widget _statusBadge(PrefixStatus status) {
    final color = switch (status) {
      PrefixStatus.active => p.success,
      PrefixStatus.reserved => p.reserved,
      PrefixStatus.planned => p.accent,
      PrefixStatus.retired => p.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        atlasLabel(status.name),
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }

  Widget _details(PrefixRecord record) => Container(
    decoration: BoxDecoration(
      color: p.detailsPanel,
      border: Border(left: BorderSide(color: p.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 14),
          child: Row(
            children: [
              Text(
                'PREFIX DETAILS',
                style: TextStyle(
                  color: p.textSecondary,
                  letterSpacing: 1.3,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Edit prefix',
                onPressed: () => _editor(record),
                icon: const Icon(Icons.edit_outlined, size: 17),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  record.cidr,
                  style: TextStyle(
                    color: p.accent,
                    fontFamily: 'monospace',
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  record.name,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 14),
                _statusBadge(record.status),
                const SizedBox(height: 26),
                CidrInspector(
                  cidr: Cidr.parse(record.cidr),
                  policy: inspectionPolicy(
                    record,
                    parent: record.parentId.isEmpty
                        ? null
                        : c.records
                              .where((r) => r.id == record.parentId)
                              .firstOrNull,
                  ),
                ),
                const SizedBox(height: 26),
                for (final field in [
                  ['Routing domain', record.routingDomain],
                  [
                    'Kind',
                    record.kind == PrefixKind.vcn
                        ? 'VCN'
                        : atlasLabel(record.kind.name),
                  ],
                  ['Customer', record.customer],
                  ['Owner', record.owner],
                  ['Environment', record.environment],
                  ['Region', record.region],
                  ['Tenancy', record.tenancy],
                  ['Compartment', record.compartment],
                  ['Parent ID', record.parentId],
                  ['Resource OCID', record.resourceId],
                  ['VCN OCID', record.vcnId],
                  ['Source', record.source],
                  [
                    'Last verified',
                    record.verifiedAt?.toLocal().toString() ?? '',
                  ],
                  ['Notes', record.notes],
                ])
                  if (field[1].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field[0].toUpperCase(),
                            style: TextStyle(
                              color: p.textSecondary,
                              fontSize: 9,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            field[1],
                            style: const TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _delete(record),
            icon: Icon(Icons.delete_outline, size: 16, color: p.danger),
            label: Text(
              'Delete prefix',
              style: TextStyle(color: p.danger, fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _conflicts() => c.conflicts.isEmpty
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 54, color: p.success),
              SizedBox(height: 20),
              Text(
                'No routing conflicts found',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: 440,
                child: Text(
                  'Checks use the local register and explicit parent relationships. Confirm import coverage before treating a range as available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, height: 1.7),
                ),
              ),
            ],
          ),
        )
      : ListView(
          padding: const EdgeInsets.all(26),
          children: [
            MessagePanel(
              message:
                  '${c.conflicts.length} overlap(s) need review. Retired records and approved parent/child containment are excluded.',
              error: true,
            ),
            const SizedBox(height: 20),
            for (final conflict in c.conflicts)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.border),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: p.danger,
                          size: 19,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          conflict.first.routingDomain,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          'OVERLAP',
                          style: TextStyle(
                            color: p.danger,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    for (final record in [conflict.first, conflict.second])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 190,
                              child: SelectableText(
                                record.cidr,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  color: p.accent,
                                ),
                              ),
                            ),
                            Expanded(child: Text(record.name)),
                            TextButton(
                              onPressed: () => _editor(record),
                              child: const Text('Edit'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 5),
                    Text(
                      conflict.reason,
                      style: TextStyle(
                        color: p.textSecondary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

  Widget _history() => c.history.isEmpty
      ? Center(
          child: Text(
            'Inventory changes will appear here.',
            style: TextStyle(color: p.textSecondary),
          ),
        )
      : ListView.separated(
          padding: const EdgeInsets.all(26),
          itemCount: c.history.length + (c.hasMoreHistory ? 1 : 0),
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (_, index) {
            if (index == c.history.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Showing the latest ${c.history.length} changes. '
                        'Older changes remain in the local database.',
                        style: TextStyle(color: p.textSecondary, fontSize: 12),
                      ),
                    ),
                    OutlinedButton(
                      key: const ValueKey('history-load-more'),
                      onPressed: () => _guard(c.loadMoreHistory),
                      child: const Text('Load more'),
                    ),
                  ],
                ),
              );
            }
            final entry = c.history[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 12,
              ),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.history_rounded, size: 20, color: p.accent),
              ),
              title: Text(entry.summary, style: const TextStyle(fontSize: 13)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  entry.action,
                  style: TextStyle(color: p.textSecondary, fontSize: 11),
                ),
              ),
              trailing: Text(
                entry.at.toLocal().toString().split('.').first,
                style: TextStyle(color: p.textSecondary, fontSize: 11),
              ),
            );
          },
        );
}
