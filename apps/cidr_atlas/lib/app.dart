import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'dialogs.dart';

const _background = Color(0xff10151f);
const _surface = Color(0xff171e2b);
const _border = Color(0xff293244);
const _muted = Color(0xff98a6bc);
const _accent = Color(0xff8fafff);

class AtlasApp extends StatelessWidget {
  const AtlasApp({super.key, required this.controller});
  final AtlasController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CIDR Atlas',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: _background,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _accent,
              brightness: Brightness.dark,
              surface: _surface),
          fontFamily: 'Arial',
          textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 14, color: Color(0xffe4eaf5)),
              bodySmall: TextStyle(color: _muted)),
          dividerColor: _border,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xff111824),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: _border)),
            labelStyle: const TextStyle(color: _muted, fontSize: 13),
          ),
          dialogTheme: DialogThemeData(
              backgroundColor: _surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18))),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffb2c7ff),
                  foregroundColor: const Color(0xff12203b),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffd6e0f2),
                  side: const BorderSide(color: _border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)))),
          tooltipTheme:
              const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
        ),
        home: _Workspace(controller: controller),
      );
}

class _Workspace extends StatefulWidget {
  const _Workspace({required this.controller});
  final AtlasController controller;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  AtlasController get c => widget.controller;
  bool _tree = false;
  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _editor([PrefixRecord? record]) async {
    final result = await showDialog<PrefixRecord>(
        context: context,
        builder: (_) => RecordEditor(records: c.records, record: record));
    if (result == null || !mounted) return;
    final combined = [
      ...c.store.list().where((r) => r.id != result.id),
      result
    ];
    final conflicts = InventoryRules.conflicts(combined)
        .where((conflict) =>
            conflict.first.id == result.id || conflict.second.id == result.id)
        .toList();
    var confirmedConflicts = false;
    if (conflicts.isNotEmpty) {
      confirmedConflicts = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                    title: const Text('This prefix has routing conflicts'),
                    content: SizedBox(
                        width: 540,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text(
                                  'Review the overlapping ranges below. You can save an observed conflict deliberately so it remains visible in the register.'),
                              const SizedBox(height: 18),
                              for (final conflict in conflicts)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: MessagePanel(
                                        message:
                                            '${conflict.first.cidr} · ${conflict.first.name}\n${conflict.second.cidr} · ${conflict.second.name}\n${conflict.reason}',
                                        error: true)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Save with conflicts'))
                    ],
                  )) ??
          false;
      if (!confirmedConflicts) return;
    }
    if (!mounted) return;
    _guard(() => c.save(result, rejectConflicts: !confirmedConflicts));
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
                content: SizedBox(
                    width: 520, child: SelectableText(atlasError(error))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ]));
  }

  Future<void> _import() async {
    final result = await showDialog<ImportPreview>(
        context: context,
        builder: (_) => ImportDialog(
            existing: c.records,
            domain: c.domain,
            proposedRecords: c.store.mergedImportRecords));
    if (result != null && mounted) {
      _guard(() => c.applyImport(result));
    }
  }

  Future<void> _export(bool csv) async {
    try {
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
                  'Remove ${record.cidr} · ${record.name} from this local register? Its change history will remain. Parent prefixes cannot be removed while children reference them.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete prefix'))
              ],
            ));
    if (confirmed == true && mounted) _guard(() => c.remove(record.id));
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
        },
        child: Focus(
            autofocus: true,
            child: AnimatedBuilder(
                animation: c,
                builder: (context, _) => Scaffold(
                      body: Row(children: [
                        _sidebar(),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              _header(),
                              Expanded(
                                  child: switch (c.page) {
                                1 => _conflicts(),
                                2 => _Planner(
                                    records: c.records, onReserve: _editor),
                                3 => _history(),
                                _ => _inventory(),
                              }),
                              Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 26),
                                  decoration: const BoxDecoration(
                                      border: Border(
                                          top: BorderSide(color: _border))),
                                  child: Row(children: [
                                    const Icon(Icons.lock_outline_rounded,
                                        size: 12, color: _muted),
                                    const SizedBox(width: 7),
                                    const Text('LOCAL INVENTORY',
                                        style: TextStyle(
                                            color: _muted,
                                            fontSize: 10,
                                            letterSpacing: 1.3)),
                                    const Spacer(),
                                    Text(
                                        '${c.records.length} prefixes  ·  ${c.domains.length} routing domains',
                                        style: const TextStyle(
                                            color: _muted, fontSize: 11)),
                                  ])),
                            ])),
                      ]),
                    ))),
      );

  Widget _sidebar() => Container(
      width: 202,
      decoration: const BoxDecoration(
          color: Color(0xff131a26),
          border: Border(right: BorderSide(color: _border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(22, 34, 18, 34),
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: const Color(0xff2b3f67),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.hub_outlined,
                      color: Color(0xffb2c7ff), size: 21)),
              const SizedBox(width: 11),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CIDR Atlas',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            letterSpacing: -.5)),
                    Text('NETWORK WORKSPACE',
                        style: TextStyle(
                            color: _muted, fontSize: 8, letterSpacing: 1.5))
                  ]),
            ])),
        const Padding(
            padding: EdgeInsets.only(left: 24, bottom: 14),
            child: Text('WORKSPACE',
                style: TextStyle(
                    color: _muted, fontSize: 10, letterSpacing: 1.6))),
        for (final item in [
          (Icons.grid_view_rounded, 'Inventory'),
          (Icons.shield_outlined, 'Conflicts'),
          (Icons.account_tree_outlined, 'Planner'),
          (Icons.history_rounded, 'History')
        ].indexed)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Material(
                  color: c.page == item.$1
                      ? const Color(0xff24334e)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => c.navigate(item.$1),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 13),
                          child: Row(children: [
                            Icon(item.$2.$1,
                                size: 19,
                                color: c.page == item.$1 ? _accent : _muted),
                            const SizedBox(width: 12),
                            Text(item.$2.$2,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: c.page == item.$1
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: c.page == item.$1
                                        ? Colors.white
                                        : _muted)),
                            if (item.$1 == 1 && c.conflicts.isNotEmpty) ...[
                              const Spacer(),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: const Color(0xff5d343a),
                                      borderRadius: BorderRadius.circular(5)),
                                  child: Text('${c.conflicts.length}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xffffa9a9))))
                            ],
                          ]))))),
        const Spacer(),
        Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xff1b2535),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border)),
                child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.desktop_mac_rounded,
                            color: _accent, size: 16),
                        SizedBox(width: 8),
                        Text('Local-first',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600))
                      ]),
                      SizedBox(height: 9),
                      Text(
                          'Your address plan, on this Mac. Import offline. Plan with confidence.',
                          style: TextStyle(
                              color: _muted, fontSize: 11, height: 1.6)),
                    ]))),
        const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 18, 22),
            child: Text('v0.1  ·  MACOS PREVIEW',
                style: TextStyle(
                    color: Color(0xff68778e),
                    fontSize: 9,
                    letterSpacing: 1.1))),
      ]));

  Widget _header() {
    const titles = [
      'Address inventory',
      'Routing conflicts',
      'Allocation planner',
      'Change history'
    ];
    const subtitles = [
      'A clear view of every network you own.',
      'Review overlapping ranges in connected address spaces.',
      'Find the next available space in your address plan.',
      'A local audit trail of inventory changes.'
    ];
    return Container(
        padding: const EdgeInsets.fromLTRB(26, 27, 26, 23),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border))),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(titles[c.page],
                    style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.7)),
                const SizedBox(height: 7),
                Text(subtitles[c.page],
                    style: const TextStyle(color: _muted, fontSize: 12))
              ])),
          IconButton(
              tooltip: 'Refresh from local database',
              onPressed: () => _guard(c.refresh),
              icon: const Icon(Icons.refresh_rounded, size: 20, color: _muted)),
          const SizedBox(width: 5),
          OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_download_outlined, size: 17),
              label: const Text('Import', style: TextStyle(fontSize: 12))),
          const SizedBox(width: 9),
          PopupMenuButton<bool>(
              tooltip: 'Export all inventory',
              onSelected: _export,
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: false,
                        child: Text('All inventory → JSON backup')),
                    const PopupMenuItem(
                        value: true, child: Text('All inventory → CSV'))
                  ],
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                      border: Border.all(color: _border),
                      borderRadius: BorderRadius.circular(9)),
                  child: const Row(children: [
                    Icon(Icons.file_upload_outlined, size: 17),
                    SizedBox(width: 7),
                    Text('Export all', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 4),
                    Icon(Icons.expand_more, size: 15)
                  ]))),
          const SizedBox(width: 9),
          FilledButton.icon(
              onPressed: () => _editor(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New prefix',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        ]));
  }

  Widget _inventory() => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
            child: Row(children: [
              Expanded(
                  child: _metric('TOTAL PREFIXES', '${c.records.length}',
                      Icons.lan_outlined, _accent)),
              const SizedBox(width: 12),
              Expanded(
                  child: _metric(
                      'ACTIVE',
                      '${c.records.where((r) => r.status == PrefixStatus.active).length}',
                      Icons.radio_button_checked,
                      const Color(0xff77d8b4))),
              const SizedBox(width: 12),
              Expanded(
                  child: _metric(
                      'PLANNED / RESERVED',
                      '${c.records.where((r) => r.status == PrefixStatus.planned || r.status == PrefixStatus.reserved).length}',
                      Icons.bookmark_border,
                      const Color(0xffdbc18b))),
              const SizedBox(width: 12),
              Expanded(
                  child: _metric(
                      'CONFLICTS',
                      '${c.conflicts.length}',
                      Icons.shield_outlined,
                      c.conflicts.isEmpty
                          ? const Color(0xff77d8b4)
                          : const Color(0xffff8c8c))),
            ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 18),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (value) => c.updateFilters(query: value),
                      decoration: const InputDecoration(
                          hintText: 'Search CIDRs, names, owners…',
                          prefixIcon: Icon(Icons.search, size: 19),
                          suffixText: '⌘F'))),
              const SizedBox(width: 10),
              SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                      key: ValueKey('domain-${c.domain}-${c.domains.length}'),
                      initialValue: c.domain ?? '',
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Routing domain'),
                      items: [
                        const DropdownMenuItem(
                            value: '',
                            child: Text('All domains',
                                style: TextStyle(fontSize: 12))),
                        ...c.domains.map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12))))
                      ],
                      onChanged: (v) => c.updateFilters(
                          routingDomain: v, clearDomain: v == ''))),
              const SizedBox(width: 10),
              SizedBox(
                  width: 132,
                  child: DropdownButtonFormField<PrefixStatus?>(
                      key: ValueKey('status-${c.status}'),
                      initialValue: c.status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('All statuses',
                                style: TextStyle(fontSize: 12))),
                        ...PrefixStatus.values.map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(atlasLabel(s.name),
                                style: const TextStyle(fontSize: 12))))
                      ],
                      onChanged: (v) =>
                          c.updateFilters(state: v, clearStatus: v == null))),
              const SizedBox(width: 10),
              Tooltip(
                  message: 'Can I use this CIDR?',
                  child: IconButton.filledTonal(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => CheckerDialog(
                              records: c.records, domain: c.domain)),
                      icon: const Icon(Icons.rule_rounded, size: 21))),
            ])),
        Expanded(
            child: c.records.isEmpty
                ? _emptyInventory()
                : LayoutBuilder(
                    builder: (context, constraints) => Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _inventoryTable()),
                              if (constraints.maxWidth >= 1000 &&
                                  c.selected != null)
                                SizedBox(
                                    width: 290, child: _details(c.selected!)),
                            ]))),
      ]);

  Widget _metric(String title, String value, IconData icon, Color color) =>
      Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 9, letterSpacing: 1.1, color: _muted)),
              const Spacer(),
              Icon(icon, size: 16, color: color)
            ]),
            const SizedBox(height: 13),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w600)),
          ]));

  Widget _emptyInventory() => Center(
      child: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                    color: const Color(0xff1d2b42),
                    borderRadius: BorderRadius.circular(24)),
                child: const Icon(Icons.account_tree_outlined,
                    size: 38, color: _accent)),
            const SizedBox(height: 24),
            const Text('Build your address map',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.5)),
            const SizedBox(height: 12),
            const Text(
                'Import an OCI inventory or reserve your first prefix. Keep allocations, VCNs, and subnets together in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, height: 1.7, fontSize: 14)),
            const SizedBox(height: 25),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_download_outlined, size: 17),
                  label: const Text('Import inventory')),
              const SizedBox(width: 12),
              OutlinedButton(
                  onPressed: () => _editor(), child: const Text('Add a prefix'))
            ]),
            const SizedBox(height: 22),
            TextButton(
                onPressed: () => _guard(c.loadDemo),
                child: const Text('Explore with fictional sample data',
                    style: TextStyle(color: _muted, fontSize: 12))),
          ])));

  Widget _inventoryTable() {
    final records = c.filtered;
    return Container(
        margin: const EdgeInsets.fromLTRB(26, 0, 26, 24),
        decoration: BoxDecoration(
            color: _surface,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(11)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
              child: Row(children: [
                Text('${records.length} prefixes',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 10),
                const Text('Select a row to inspect',
                    style: TextStyle(color: _muted, fontSize: 11)),
                const Spacer(),
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
                            color: _accent))),
              ])),
          const Divider(height: 1),
          Expanded(
              child: records.isEmpty
                  ? const Center(
                      child: Text('No prefixes match your filters.',
                          style: TextStyle(color: _muted)))
                  : _tree
                      ? ListView(children: _hierarchy(records))
                      : LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                      width: constraints.maxWidth < 700
                                          ? 700
                                          : constraints.maxWidth,
                                      child: Column(children: [
                                        _tableHeader(),
                                        Expanded(
                                            child: ListView.builder(
                                                itemCount: records.length,
                                                itemBuilder: (_, index) =>
                                                    _tableRow(records[index]))),
                                      ]))))),
        ]));
  }

  Widget _tableHeader() => Container(
      height: 36,
      color: const Color(0xff141b28),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Row(children: [
        SizedBox(
            width: 164,
            child: Text('PREFIX / KIND',
                style:
                    TextStyle(color: _muted, fontSize: 9, letterSpacing: 1))),
        Expanded(
            flex: 3,
            child: Text('NAME',
                style:
                    TextStyle(color: _muted, fontSize: 9, letterSpacing: 1))),
        Expanded(
            flex: 2,
            child: Text('ROUTING DOMAIN',
                style:
                    TextStyle(color: _muted, fontSize: 9, letterSpacing: 1))),
        SizedBox(
            width: 108,
            child: Text('REGION',
                style:
                    TextStyle(color: _muted, fontSize: 9, letterSpacing: 1))),
        SizedBox(
            width: 87,
            child: Text('STATUS',
                style:
                    TextStyle(color: _muted, fontSize: 9, letterSpacing: 1))),
        SizedBox(width: 28),
      ]));

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
                                  child: const Text('Close')),
                            ]));
                      })),
            ));
  }

  Widget _tableRow(PrefixRecord record) => Material(
      color: c.selectedId == record.id
          ? const Color(0xff23334e)
          : Colors.transparent,
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
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xff232c3d)))),
              child: Row(children: [
                SizedBox(
                    width: 164,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(record.cidr,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 5),
                          Text(
                              record.kind == PrefixKind.vcn
                                  ? 'VCN'
                                  : atlasLabel(record.kind.name),
                              style:
                                  const TextStyle(color: _muted, fontSize: 10))
                        ])),
                Expanded(
                    flex: 3,
                    child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(record.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                              if (record.owner.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(record.owner,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: _muted, fontSize: 10))
                              ]
                            ]))),
                Expanded(
                    flex: 2,
                    child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(record.routingDomain,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 11, color: _muted)))),
                SizedBox(
                    width: 108,
                    child: Text(record.region.isEmpty ? '—' : record.region,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _muted))),
                SizedBox(
                    width: 87,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _statusBadge(record.status))),
                const Icon(Icons.chevron_right, size: 18, color: _muted),
              ]))));

  List<Widget> _hierarchy(List<PrefixRecord> records) {
    final visible = records.map((r) => r.id).toSet();
    Widget branch(PrefixRecord record) {
      final children = records.where((r) => r.parentId == record.id).toList();
      if (children.isEmpty)
        return ListTile(
            dense: true,
            leading: Icon(
                record.kind == PrefixKind.subnet
                    ? Icons.segment
                    : Icons.lan_outlined,
                size: 18,
                color: _accent),
            title: Text('${record.cidr}  ·  ${record.name}',
                style: const TextStyle(fontSize: 12)),
            subtitle: Text(record.routingDomain,
                style: const TextStyle(fontSize: 10)),
            trailing: _statusBadge(record.status),
            onTap: () => _inspect(record));
      return ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.folder_outlined, size: 18, color: _accent),
          title: Text('${record.cidr}  ·  ${record.name}',
              style: const TextStyle(fontSize: 12)),
          subtitle:
              Text(record.routingDomain, style: const TextStyle(fontSize: 10)),
          trailing: IconButton(
              tooltip: 'Inspect prefix',
              onPressed: () => _inspect(record),
              icon: const Icon(Icons.info_outline, size: 18, color: _accent)),
          childrenPadding: const EdgeInsets.only(left: 20),
          children: [for (final child in children) branch(child)]);
    }

    return records
        .where((r) => r.parentId.isEmpty || !visible.contains(r.parentId))
        .map(branch)
        .toList();
  }

  Widget _statusBadge(PrefixStatus status) {
    final color = switch (status) {
      PrefixStatus.active => const Color(0xff77d8b4),
      PrefixStatus.reserved => const Color(0xffdbc18b),
      PrefixStatus.planned => _accent,
      PrefixStatus.retired => _muted
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(5)),
        child: Text(atlasLabel(status.name),
            style: TextStyle(fontSize: 10, color: color)));
  }

  Widget _details(PrefixRecord record) => Container(
      decoration: const BoxDecoration(
          color: Color(0xff141c28),
          border: Border(left: BorderSide(color: _border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 14),
            child: Row(children: [
              const Text('PREFIX DETAILS',
                  style: TextStyle(
                      color: _muted, letterSpacing: 1.3, fontSize: 10)),
              const Spacer(),
              IconButton(
                  tooltip: 'Edit prefix',
                  onPressed: () => _editor(record),
                  icon: const Icon(Icons.edit_outlined, size: 17))
            ])),
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(record.cidr,
                          style: const TextStyle(
                              color: _accent,
                              fontFamily: 'monospace',
                              fontSize: 21,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Text(record.name,
                          style: const TextStyle(fontSize: 16, height: 1.4)),
                      const SizedBox(height: 14),
                      _statusBadge(record.status),
                      const SizedBox(height: 26),
                      for (final field in [
                        ['Routing domain', record.routingDomain],
                        [
                          'Kind',
                          record.kind == PrefixKind.vcn
                              ? 'VCN'
                              : atlasLabel(record.kind.name)
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
                          record.verifiedAt?.toLocal().toString() ?? ''
                        ],
                        ['Notes', record.notes],
                      ])
                        if (field[1].isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(field[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: _muted,
                                            fontSize: 9,
                                            letterSpacing: .8)),
                                    const SizedBox(height: 6),
                                    SelectableText(field[1],
                                        style: const TextStyle(
                                            fontSize: 12, height: 1.5))
                                  ])),
                    ]))),
        Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
                onPressed: () => _delete(record),
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Color(0xffff8c8c)),
                label: const Text('Delete prefix',
                    style: TextStyle(color: Color(0xffff8c8c), fontSize: 12)))),
      ]));

  Widget _conflicts() => c.conflicts.isEmpty
      ? const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_outlined, size: 54, color: Color(0xff77d8b4)),
          SizedBox(height: 20),
          Text('No routing conflicts found',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          SizedBox(
              width: 440,
              child: Text(
                  'Checks use the local register and explicit parent relationships. Confirm import coverage before treating a range as available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.7)))
        ]))
      : ListView(padding: const EdgeInsets.all(26), children: [
          MessagePanel(
              message:
                  '${c.conflicts.length} overlap(s) need review. Retired records and approved parent/child containment are excluded.',
              error: true),
          const SizedBox(height: 20),
          for (final conflict in c.conflicts)
            Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _surface,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(11)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xffff8c8c), size: 19),
                        const SizedBox(width: 10),
                        Text(conflict.first.routingDomain,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        const Text('OVERLAP',
                            style: TextStyle(
                                color: Color(0xffff8c8c),
                                fontSize: 10,
                                letterSpacing: 1))
                      ]),
                      const SizedBox(height: 16),
                      for (final record in [conflict.first, conflict.second])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              SizedBox(
                                  width: 190,
                                  child: SelectableText(record.cidr,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          color: _accent))),
                              Expanded(child: Text(record.name)),
                              TextButton(
                                  onPressed: () => _editor(record),
                                  child: const Text('Edit'))
                            ])),
                      const SizedBox(height: 5),
                      Text(conflict.reason,
                          style: const TextStyle(
                              color: _muted, fontSize: 12, height: 1.5)),
                    ])),
        ]);

  Widget _history() => c.history.isEmpty
      ? const Center(
          child: Text('Inventory changes will appear here.',
              style: TextStyle(color: _muted)))
      : ListView.separated(
          padding: const EdgeInsets.all(26),
          itemCount: c.history.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final entry = c.history[index];
            return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.history_rounded,
                        size: 20, color: _accent)),
                title:
                    Text(entry.summary, style: const TextStyle(fontSize: 13)),
                subtitle: Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(entry.action,
                        style: const TextStyle(color: _muted, fontSize: 11))),
                trailing: Text(entry.at.toLocal().toString().split('.').first,
                    style: const TextStyle(color: _muted, fontSize: 11)));
          });
}

class _Planner extends StatefulWidget {
  const _Planner({required this.records, required this.onReserve});
  final List<PrefixRecord> records;
  final void Function(PrefixRecord) onReserve;
  @override
  State<_Planner> createState() => _PlannerState();
}

class _PlannerState extends State<_Planner> {
  final _pool = TextEditingController();
  final _domain = TextEditingController();
  final _length = TextEditingController(text: '24');
  PrefixRecord? _selectedPool;
  List<Cidr> _available = [];
  String? _error;
  bool _ran = false;
  @override
  void didUpdateWidget(covariant _Planner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.records, widget.records)) {
      _ran = false;
      _available = [];
      if (_selectedPool != null) {
        final latest = widget.records
            .where((r) =>
                r.id == _selectedPool!.id &&
                r.kind != PrefixKind.subnet &&
                r.status != PrefixStatus.retired)
            .firstOrNull;
        _selectedPool = latest;
        if (latest != null) {
          _pool.text = latest.cidr;
          _domain.text = latest.routingDomain;
        }
      }
    }
  }

  @override
  void dispose() {
    _pool.dispose();
    _domain.dispose();
    _length.dispose();
    super.dispose();
  }

  void _find() {
    try {
      final pool = Cidr.parse(_pool.text.trim());
      final length = int.tryParse(_length.text.trim());
      if (length == null)
        throw const FormatException('Prefix length must be a whole number.');
      if (_domain.text.trim().isEmpty)
        throw const FormatException('Enter an explicit routing domain.');
      final results = InventoryRules.available(
          parent: pool,
          prefixLength: length,
          records: widget.records,
          parentId: _selectedPool?.id,
          routingDomain: _domain.text.trim(),
          limit: 12);
      setState(() {
        _available = results;
        _ran = true;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = atlasError(error);
        _ran = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Find available prefixes',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              const Text(
                                  'Select an existing pool or enter a parent range. Suggestions exclude active, reserved, and planned ranges in the same routing domain.',
                                  style: TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                      height: 1.7)),
                              const SizedBox(height: 24),
                              DropdownButtonFormField<String>(
                                  key: ValueKey('pool-${_selectedPool?.id}'),
                                  initialValue: _selectedPool?.id ?? '',
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Existing parent pool (optional)'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: '',
                                        child: Text('Enter a range manually')),
                                    ...widget.records
                                        .where((r) =>
                                            r.kind != PrefixKind.subnet &&
                                            r.status != PrefixStatus.retired)
                                        .map((r) => DropdownMenuItem(
                                            value: r.id,
                                            child: Text(
                                                '${r.cidr} · ${r.name} · ${r.routingDomain}',
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                  ],
                                  onChanged: (id) => setState(() {
                                        _selectedPool = id == ''
                                            ? null
                                            : widget.records
                                                .firstWhere((r) => r.id == id);
                                        if (_selectedPool != null) {
                                          _pool.text = _selectedPool!.cidr;
                                          _domain.text =
                                              _selectedPool!.routingDomain;
                                        }
                                        _ran = false;
                                      })),
                              const SizedBox(height: 18),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                        flex: 3,
                                        child: TextField(
                                            controller: _pool,
                                            onChanged: (_) => setState(() {
                                                  _selectedPool = null;
                                                  _ran = false;
                                                }),
                                            decoration: const InputDecoration(
                                                labelText: 'Parent CIDR',
                                                hintText: '10.64.0.0/16'))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        flex: 3,
                                        child: TextField(
                                            controller: _domain,
                                            onChanged: (_) => setState(() {
                                                  _selectedPool = null;
                                                  _ran = false;
                                                }),
                                            decoration: const InputDecoration(
                                                labelText: 'Routing domain',
                                                hintText: 'corporate'))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: TextField(
                                            controller: _length,
                                            onChanged: (_) =>
                                                setState(() => _ran = false),
                                            decoration: const InputDecoration(
                                                labelText: 'Length',
                                                prefixText: '/'))),
                                  ]),
                              const SizedBox(height: 22),
                              FilledButton.icon(
                                  onPressed: _find,
                                  icon:
                                      const Icon(Icons.manage_search, size: 19),
                                  label: const Text('Find available space')),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 18),
                                    child: MessagePanel(
                                        message: _error!, error: true)),
                            ])),
                    if (_ran) ...[
                      const SizedBox(height: 24),
                      Text(
                          _available.isEmpty
                              ? 'No available space at this prefix length'
                              : '${_available.length} suggestions',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      const Text(
                          'Suggestions reflect this register only and are not reservations. Use Reserve to review ownership and save a prefix.',
                          style: TextStyle(
                              color: _muted, fontSize: 12, height: 1.6)),
                      const SizedBox(height: 16),
                      for (final range in _available)
                        Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                                color: _surface,
                                border: Border.all(color: _border),
                                borderRadius: BorderRadius.circular(9)),
                            child: Row(children: [
                              const Icon(Icons.check_circle_outline,
                                  color: Color(0xff77d8b4), size: 18),
                              const SizedBox(width: 14),
                              SelectableText(range.canonical,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', color: _accent)),
                              const SizedBox(width: 20),
                              Text('${range.addressCount} addresses',
                                  style: const TextStyle(
                                      color: _muted, fontSize: 12)),
                              const Spacer(),
                              TextButton(
                                  onPressed: () => widget.onReserve(PrefixRecord(
                                      id:
                                          'manual:${DateTime.now().microsecondsSinceEpoch}',
                                      cidr: range.canonical,
                                      name: '',
                                      routingDomain: _domain.text.trim(),
                                      kind:
                                          _selectedPool?.kind == PrefixKind.vcn
                                              ? PrefixKind.subnet
                                              : PrefixKind.vcn,
                                      parentId: _selectedPool?.id ?? '',
                                      tenancy: _selectedPool?.tenancy ?? '',
                                      region: _selectedPool?.region ?? '',
                                      customer: _selectedPool?.customer ?? '',
                                      environment:
                                          _selectedPool?.environment ?? '',
                                      vcnId:
                                          _selectedPool?.kind == PrefixKind.vcn
                                              ? _selectedPool!.resourceId
                                              : '',
                                      source: 'manual')),
                                  child: const Text('Reserve')),
                            ])),
                    ],
                  ]))));
}
