# CIDR Atlas implementation contract

Author: Sergio Farfan <sergio.farfan@gmail.com>

Monorepo: `packages/cidr_core` (pure Dart), `packages/cidr_data` (Dart SQLite/imports), `packages/cidr_cli`, `apps/cidr_atlas` (Flutter macOS first).

Core public API, exported from `package:cidr_core/cidr_core.dart`:

- `Cidr.parse(String input)` rejects invalid prefixes and host bits rather than silently changing the requested network. Properties: `canonical` String, `prefixLength` int, `version` int, `addressCount` BigInt. Methods: `contains(Cidr)`, `overlaps(Cidr)`.
- enums `PrefixKind { allocation, vcn, subnet }`, `PrefixStatus { planned, reserved, active, retired }`.
- Immutable `PrefixRecord`: required named String `id`, `cidr`, `name`, `routingDomain`; named `kind` default `PrefixKind.vcn`, `status` default `PrefixStatus.reserved`; optional String fields default empty: `customer`, `tenancy`, `region`, `compartment`, `environment`, `owner`, `resourceId`, `vcnId`, `parentId`, `notes`, `source`; nullable DateTime `verifiedAt`. `toJson()`, `PrefixRecord.fromJson(Map<String,dynamic>)`, `copyWith(...)`.
- `Conflict`: `PrefixRecord first`, `second`; String `reason`.
- `InventoryRules.conflicts(List<PrefixRecord>)` returns List<Conflict>. Only same routing domain conflicts. Retired prefixes ignored. Valid parent containment requires explicit, valid parentId chain OR VCN/subnet OCI resource relationship (matching vcn.resourceId and subnet.vcnId, same tenancy/region/domain). Arbitrary numeric containment is a conflict. Nonoverlapping unrelated resources are allowed.
- `InventoryRules.validate(List<PrefixRecord>)` returns List<String> for invalid CIDRs, blank identities/domains, duplicate ids, invalid/missing parent links, containment/kind mismatch and cycles. Conflicts remain reviewable, not structural validation errors.
- `InventoryRules.available({required Cidr parent, required int prefixLength, required List<PrefixRecord> records, required String routingDomain, String? parentId, int limit = 8})` returns List<Cidr>; ignores retired entries. With parentId, validates the selected pool and ignores only that record and its explicit valid ancestors. Without it, every overlapping existing range blocks. Reject impossible prefix lengths.

Data API exported from `package:cidr_data/cidr_data.dart`:

- `InventoryStore.open(String path)`, `InventoryStore.memory()`; synchronous `List<PrefixRecord> list()`, `void save(PrefixRecord, {bool rejectConflicts = false})`, `void delete(String id)`, `void saveAll(List<PrefixRecord>)`, `List<AuditEntry> history({int limit = 100})`, `void close()`.
- `AuditEntry`: String `action`, `summary`; DateTime `at`.
- Atomic saves validate combined structure. rejectConflicts checks the candidate within the same write transaction for allocation workflows. Store enforces structure but allows conflict records so discovered overlaps are visible.
- `ImportPreview`: List<PrefixRecord> `records`; List<String> `errors`, `warnings`; String `source`; bool `get canApply` (nonempty records and no errors).
- `InventoryImport.csv(String, {List<PrefixRecord> existingRecords = const []})`, `InventoryImport.json(String, {required String routingDomain, List<PrefixRecord> existingRecords = const []})`, `InventoryImport.exportCsv(List<PrefixRecord>)`, `InventoryImport.exportJson(List<PrefixRecord>)`.
- `InventoryStore.mergedImportRecords(ImportPreview)` returns the full dry-run inventory using the same merge rules as applyImport; `InventoryStore.applyImport(ImportPreview)` applies atomically, merging by id and preserving existing owner/notes/status/parentId/environment/customer where source is OCI. No absent entries deleted or retired. Audit coverage warning always explicit.

UI: dark desktop workspace titled CIDR Atlas, sidebar Inventory / Conflicts / History, search and domain/status filters, selectable table, details pane, add/edit dialog, CIDR checker, available subnet planner, import preview, JSON/CSV export, empty state with optional clearly labeled demo data. No production-looking data preloaded. Uses synchronous store via controller; catch errors and show readable messages. Local DB is under path_provider's Application Support/cidr_atlas/inventory.sqlite.

Shared contract changes must remain consistent across the domain, persistence, CLI, and application packages.
