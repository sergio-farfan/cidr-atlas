// CIDR Atlas
// Inventory state and application operations.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/foundation.dart';

class AtlasController extends ChangeNotifier {
  AtlasController(this.store, {required this.databasePath}) {
    refresh();
  }

  final InventoryStore store;
  final String databasePath;
  List<PrefixRecord> records = [];
  List<Conflict> conflicts = [];
  List<AuditEntry> history = [];
  String search = '';
  String? domain;
  PrefixStatus? status;
  String? selectedId;
  int page = 0;

  List<String> get domains =>
      (records.map((r) => r.routingDomain).toSet().toList()..sort());
  List<PrefixRecord> get filtered {
    final query = search.toLowerCase().trim();
    return records.where((r) {
      if (domain != null && r.routingDomain != domain) return false;
      if (status != null && r.status != status) return false;
      return query.isEmpty ||
          [
            r.cidr,
            r.name,
            r.customer,
            r.routingDomain,
            r.tenancy,
            r.region,
            r.compartment,
            r.environment,
            r.owner,
            r.resourceId,
            r.notes
          ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  PrefixRecord? get selected {
    for (final record in records) {
      if (record.id == selectedId) return record;
    }
    return null;
  }

  void refresh() {
    records = store.list();
    conflicts = InventoryRules.conflicts(records);
    history = store.history();
    if (domain != null && !domains.contains(domain)) domain = null;
    if (selectedId != null && !records.any((r) => r.id == selectedId))
      selectedId = null;
    notifyListeners();
  }

  void updateFilters(
      {String? query,
      String? routingDomain,
      PrefixStatus? state,
      bool clearDomain = false,
      bool clearStatus = false}) {
    if (query != null) search = query;
    if (clearDomain) {
      domain = null;
    } else if (routingDomain != null) {
      domain = routingDomain;
    }
    if (clearStatus) {
      status = null;
    } else if (state != null) {
      status = state;
    }
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void navigate(int index) {
    page = index;
    notifyListeners();
  }

  void save(PrefixRecord record, {bool rejectConflicts = false}) {
    store.save(record, rejectConflicts: rejectConflicts);
    selectedId = record.id;
    refresh();
  }

  void remove(String id) {
    store.delete(id);
    if (selectedId == id) selectedId = null;
    refresh();
  }

  void applyImport(ImportPreview preview) {
    store.applyImport(preview);
    refresh();
  }

  void loadDemo() {
    const domain = 'demo-corporate';
    store.saveAll([
      PrefixRecord(
          id: 'demo-pool',
          cidr: '10.64.0.0/16',
          name: 'Western region allocation',
          routingDomain: domain,
          kind: PrefixKind.allocation,
          status: PrefixStatus.active,
          customer: 'Example Company',
          owner: 'Network Architecture',
          notes: 'Fictional sample inventory.'),
      PrefixRecord(
          id: 'demo-vcn',
          cidr: '10.64.0.0/20',
          name: 'Production VCN',
          routingDomain: domain,
          status: PrefixStatus.active,
          parentId: 'demo-pool',
          customer: 'Example Company',
          tenancy: 'demo-tenancy',
          region: 'us-phoenix-1',
          environment: 'Production',
          owner: 'Platform Team',
          resourceId: 'demo-vcn-resource'),
      PrefixRecord(
          id: 'demo-app',
          cidr: '10.64.1.0/24',
          name: 'Application subnet',
          routingDomain: domain,
          kind: PrefixKind.subnet,
          status: PrefixStatus.active,
          parentId: 'demo-vcn',
          tenancy: 'demo-tenancy',
          region: 'us-phoenix-1',
          vcnId: 'demo-vcn-resource'),
      PrefixRecord(
          id: 'demo-db',
          cidr: '10.64.2.0/24',
          name: 'Database subnet',
          routingDomain: domain,
          kind: PrefixKind.subnet,
          status: PrefixStatus.active,
          parentId: 'demo-vcn',
          tenancy: 'demo-tenancy',
          region: 'us-phoenix-1',
          vcnId: 'demo-vcn-resource'),
      PrefixRecord(
          id: 'demo-next',
          cidr: '10.64.16.0/20',
          name: 'AI platform reservation',
          routingDomain: domain,
          status: PrefixStatus.reserved,
          parentId: 'demo-pool',
          region: 'us-phoenix-1',
          environment: 'Development',
          owner: 'AI Infrastructure'),
      PrefixRecord(
          id: 'demo-isolated',
          cidr: '10.64.0.0/20',
          name: 'Isolated customer VCN',
          routingDomain: 'demo-customer-isolated',
          status: PrefixStatus.planned,
          customer: 'Example Customer',
          notes: 'Address reuse is valid in this isolated routing domain.'),
    ]);
    refresh();
  }
}
