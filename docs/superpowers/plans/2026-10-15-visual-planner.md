# Visual Planner Implementation Plan

Author: Sergio Farfan <sergio.farfan@gmail.com>

**Goal:** Deliver the approved visual address planner, shared CIDR inspector,
exact open-slot counts, and explainable conflict-free recommendations, then
publish a verified universal macOS DMG as v0.2.0 in the private repository.

**Architecture:** Pure Dart calculations remain in cidr_core; both clients use
the same planning result. Existing SQLite transactions enforce final reservation
conflicts, and the decision is preserved in the new record's notes. The Flutter
workspace visualizes hierarchy, intervals and bounded candidates. OCI discovery
and offline imports retain their existing contracts.

**Tech stack:** Flutter 3.47.7, Dart 3.13.5, SQLite, existing dependencies.

**Spec:** docs/superpowers/specs/2026-10-15-visual-network-planning-design.md,
approved by Sergio Farfan on 2026-10-15.

## Constraints

- Exact BigInt IPv4/IPv6 arithmetic, canonical CIDRs, explicit parent/domain.
- Planned/reserved/active ranges block; retired ranges do not. Numerical
  containment never creates hierarchy. Display filters never remove blockers.
- Candidate availability is scoped to known inventory, not proof of live vacancy.
- OCI IPv4 subnet eligibility is /16 through /30, with three reserved addresses.
  IPv6 shows exact raw capacity; provider assignable count remains unresolved.
- No new OCI resource collection types or credentials, no cloud writes, no
  topology inference. Scoped read-only diagnosis of existing discovery is allowed
  when explicitly requested.
- Preserve OCI CLI and CSV/JSON preview, atomic import and planning metadata.
- Professional purpose/author headers: Sergio Farfan <sergio.farfan@gmail.com>.
  Sole project authorship and no internal workflow notes in source/product docs.
- Do not commit generated builds, databases, real inventory or SDK paths.

## Review focus

- Exact free-slot totals must exceed rendered candidate limits when appropriate.
- A partially occupied aligned slot is unavailable even if enough raw free IPs remain.
- Changing inputs or inventory invalidates candidates before they can be reserved.
- OCI /31 and /32 remain generic calculations, not eligible OCI subnet suggestions.
- Reservation rechecks SQLite state and cannot override conflicts from a stale result.

## Shared core API

Create `lib/src/address_planner.dart`, exported by cidr_core. Public types:

- `enum AddressPolicy { generic, ociIpv4Subnet }`
- `enum DemandBasis { current, peak }`
- `AddressDemand({required BigInt addresses, required int growthPercent,
  BigInt? additionalAddresses, DemandBasis basis = DemandBasis.current})`.
  Fields reflect inputs; `targetAddresses` uses ceiling integer percentage plus
  fixed additional demand. Reject nonpositive demand, negative growth/additional.
  Peak inputs still accept explicitly chosen growth; never add hidden growth.
- `AddressInterval({required BigInt start, required BigInt end, required int version})`:
  inclusive bounds, `BigInt get addressCount`, `String get firstAddress`,
  `String get lastAddress`.
- `CidrDetails.from(Cidr cidr, {AddressPolicy policy = AddressPolicy.generic})`:
  `cidr`, `int hostBits`, `BigInt totalAddresses`, `String firstAddress`,
  `String lastAddress`, `String? subnetMask`, `BigInt? assignableAddresses`,
  `String? assignableFirst`, `String? assignableLast`, `String policyNote`;
  `Cidr containingSupernet(int prefixLength)`, `Map<String,dynamic> toJson()`.
  Ineligible provider prefixes keep raw details but no assignable count.
- `AddressSpaceSummary`: `Cidr parent`, `List<AddressInterval> freeIntervals`,
  `blockedIntervals`, `BigInt totalAddresses`, `freeAddresses`, `blockedAddresses`,
  `totalSlots`, `freeSlots`, `Cidr? largestFreeBlock`.
- `AllocationRecommendation`: `Cidr cidr`, `CidrDetails details`,
  `String rationale` containing the sizing inputs, policy, placement reason and
  coverage caveat. This text can be appended to notes without changing storage.
- `AllocationPlan`: `AddressSpaceSummary summary`, `int prefixLength`,
  `BigInt? targetAddresses`, `List<AllocationRecommendation> candidates`,
  `List<String> warnings`, `Map<String,dynamic> toJson()`.
- `AddressPlanner.plan({required Cidr parent, required String routingDomain,
  required List<PrefixRecord> records, String? parentId, int? prefixLength,
  AddressDemand? demand, AddressPolicy policy = AddressPolicy.generic,
  int limit = 12}) -> AllocationPlan`.

Exactly one of prefixLength/demand is supplied. Demand mode initially requires
OCI IPv4 subnet policy; generic/IPv6 continue using explicit prefix length.
Failure to fit demand is a clear error; a valid size with no aligned space returns
an empty candidate list and zero freeSlots. JSON serializes BigInt as decimal
strings. Additional constructors/model serialization details belong to the builder.

## Status (reviewed 2026-10-16)

Delivered in v0.2.0 (tag `v0.2.0`, published; see `PROJECT.md` at commit `8879f0a`) except where an item is
marked **Open**. Evidence pointers name test files or release records. Notes
marked **Since** record later changes from the 2026-10-16 review remediation.

## Task 1: Exact capacity and recommendations

**Own:** packages/cidr_core/**.

- [x] Write failing details tests for IPv4 masks/ranges, /0,/31,/32, IPv6 /0,/128,
  containing supernets and OCI eligibility; implement the documented API.
  Evidence: `packages/cidr_core/test/address_planner_test.dart`, group `CIDR details`.
- [x] Add failing interval/slot tests, then refactor the existing blocker logic
  into one reusable internal calculation shared with InventoryRules.available.
  Preserve its original first-address ordering/API. Test hierarchy/domain reuse,
  overlapping/nested blockers, partial slots, retired ranges and huge IPv6 spaces.
  Evidence: `packages/cidr_core/lib/src/planning_space.dart`; `packages/cidr_core/test/address_planner_test.dart`, group
  `exact address space`.
- [x] Add demand and ranking regressions: 100 +20% +4 ->124 ->OCI /25 with125
  assignable; /26 fails; no-fit; exact growth rounding and invalid inputs.
  Evidence: `packages/cidr_core/test/address_planner_test.dart`, groups `address demand` and `recommendations`.
- [x] Implement a deterministic best-fit heuristic: decompose free intervals
  into maximal aligned CIDRs, prefer the smallest fitting containing free block,
  use aligned edge placement/address tie-breaks, emit bounded suggestions and
  explanations while exact counts remain independent of limits.
  Evidence: `packages/cidr_core/lib/src/address_planner.dart`; `packages/cidr_core/test/address_planner_test.dart`, group
  `recommendations`.
- [x] Run format, analyzer and full core tests; report red/green evidence and
  final API before consumers finish. Root coordinates commits after review.
  Evidence: v0.2.0 verification in `PROJECT.md` at commit `8879f0a`.

## Task 2: Visual planner and inspector

**Own:** new apps/cidr_atlas/lib/visual_planner.dart,
lib/cidr_inspector.dart and their new widget tests. Do not edit app.dart.

**Produces:** `VisualPlanner({required List<PrefixRecord> records,
required void Function(PrefixRecord) onReserve})` and
`CidrInspector({required Cidr cidr, AddressPolicy policy = AddressPolicy.generic})`.
The proposed reserved PrefixRecord carries a unique ID, valid parent/kind/scope,
status reserved, and the complete recommendation rationale in notes.

- [x] Write failing widget tests for explicit pool/domain selection, prefix and
  host-demand modes, visible required growth/additional controls, policy
  eligibility, exact summaries and bounded open-slot results.
  Evidence: `apps/cidr_atlas/test/visual_planner_test.dart` (`planning requires an explicit routing domain`, `exact
  bounded planning and responsive selection`, `demand exposes explicit growth
  and extra demand`, `OCI subnet policy rejects a generic slash 31`).
- [ ] Implement the established dark app styling with responsive controls,
  ordered free/blocked range visualization, labels/patterns, stable zoom/fit/reset,
  candidate selection and inspector. Use all records for planning regardless of
  presentation filters. Hierarchy groups multiple OCI CIDRs by resource identity
  and shows unresolved context accurately. No claimed network connectivity.
  - Delivered: styling, responsive controls, ordered free/blocked map, zoom and
    reset, candidate selection, inspector, OCI resource grouping and unresolved
    context (`apps/cidr_atlas/test/visual_planner_test.dart`). Planning always uses all records.
  - **Open:** distinct labels and patterns per status (active, reserved,
    planned, conflict, retired) on the map, which shows only free and blocked
    space; planner presentation filters do not exist yet. Review finding #64.
  - **Since:** Fit was replaced by **Zoom to candidate**, and zoom anchors on
    the selected candidate.
- [x] Exercise sidebar hierarchy/resource selection, multiple VCN CIDRs, conflict
  markers, partial coverage wording, no automatic collection, keyboard access,
  and 1100x740 /1440x900 layouts.
  Evidence: `apps/cidr_atlas/test/visual_planner_test.dart` (`one OCI resource groups CIDRs while unresolved context stays
  visible`, `partial slots block and overlapping records display conflicts`,
  `large IPv6 counts stay exact and keyboard selects candidate`, responsive
  layout tests).
- [x] Test candidate invalidation after input edits/inventory refresh; reservation
  callback only for current results. Default child kind is subnet under VCN and
  VCN under allocation; host-demand mode requires subnet intent.
  Evidence: `apps/cidr_atlas/test/visual_planner_test.dart` (`input edits invalidate selected candidates before
  reservation`, `inventory changes and pool retirement invalidate a plan`).
- [x] Run owned-file format, Flutter analyze and full widget suite. Report evidence.
  Evidence: v0.2.0 verification in `PROJECT.md` at commit `8879f0a`.

## Task 3: CLI and persistence checks

**Own:** packages/cidr_cli/** and new packages/cidr_data/test/planning_test.dart.
Existing data APIs stay compatible. Add `InventoryStore.reserve(PrefixRecord)`
to enforce new identity and conflict rejection atomically; existing save/import
behavior remains unchanged.

- [x] Add failing CLI tests for `recommend --pool CIDR --routing-domain DOMAIN`
  with `--parent ID` optional; `--prefix N` or `--addresses N`; explicit
  `--growth-percent N` required with addresses; `--additional N` default0;
  `--basis current|peak`; `--policy generic|oci_ipv4`; `--limit N` default12;
  `--format text|json`. Demand defaults to OCI IPv4; prefix defaults generic.
  Evidence: `packages/cidr_cli/test/recommendation_test.dart`.
- [x] Use AddressPlanner directly, with preview-only default. `--apply` explicitly
  reserves the first ranked candidate and requires `--name`; `--kind vcn|subnet`
  defaults based on parent, otherwise subnet. Reject any incompatible hierarchy
  or OCI demand/non-subnet intent. Append rationale to optional `--notes`.
  Evidence: `packages/cidr_cli/lib/src/recommendation.dart`; `packages/cidr_cli/test/recommendation_test.dart`.
- [x] Save with InventoryStore.reserve using the existing atomic transaction. Preserve
  all existing commands/imports; errors retain current exit conventions.
  Evidence: `recommendation.dart` calls `store.reserve`. **Since:** `cidrctl
  reserve` also writes through `InventoryStore.reserve`.
- [x] Add meaningful data tests for persisted rationale through reopen/JSON backup
  and OCI refresh, plus two-connection stale-candidate rejection with unchanged
  inventory/history. Do not overwrite existing IDs on recommendation apply.
  Evidence: `packages/cidr_data/test/planning_test.dart`.
- [x] Format/analyze/test CLI and data; native compile and fictional temporary-DB
  smoke for preview/apply/no-fit/stale reservation. No real OCI calls.
  Evidence: v0.2.0 verification in `PROJECT.md` at commit `8879f0a` (compiled-CLI fictional
  temporary-database checks; the two-connection stale case in data tests).

## Task 4: Application integration and field guidance

**Own:** root integrates app.dart, oci_dialog.dart, existing widget tests,
version metadata and documentation. Separate from Task2 files.

- [x] Replace the old planner implementation with VisualPlanner, preserving
  navigation and existing pool behavior. Add CidrInspector to record details.
  Evidence: `apps/cidr_atlas/lib/app.dart`; `apps/cidr_atlas/test/workspace_test.dart`
  (`planner finds ranges within an explicitly selected pool`).
- [x] Reservation editor retains proposed rationale and saves with strict conflict
  rejection. Do not expose the manual conflict-override path for recommendations.
  Evidence: `apps/cidr_atlas/test/planner_integration_test.dart` (`reviewed recommendation saves strictly and retains its
  decision`, `stale recommendation cannot use manual conflict override`).
- [x] Explain Routing domain in OCI discovery with an example and concise helper
  text: a local overlap-check scope shared by connected address plans. Keep it
  explicitly required; never default it to tenancy, profile or region.
  Evidence: `apps/cidr_atlas/lib/oci_dialog.dart` helper text;
  `apps/cidr_atlas/test/oci_dialog_test.dart` (`manual scope works after IAM
  selector failure and requires a routing domain`).
- [x] Test successful reservation and stale conflict rejection through real store,
  both offline and OCI import entry retention, and required-domain guidance.
  Evidence: `apps/cidr_atlas/test/planner_integration_test.dart`;
  `apps/cidr_atlas/test/oci_dialog_test.dart` (`manual scope works after IAM
  selector failure and requires a routing domain`; entry retention through
  `discovery help retains scope input without network requests` and `import
  help retains preview and expandable coverage without writes`). **Since:**
  end-to-end reservation through `AtlasApp`, including a concurrent conflicting
  write.

## Task 5: Review, verification and release

- [x] Review each deliverable independently and resolve material findings; then
  review the whole branch. Verify sole project author identity.
  Evidence: `PROJECT.md` at commits `7b75532` (scoped and integrated reviews)
  and `8879f0a` (author and committer identity).
- [ ] Run all package analyzers/tests and Flutter checks. Build native macOS app
  and CLI; smoke planner/inspector/reservation with fictional data and preserve
  any existing user inventory. Do not read real OCI config in automated checks.
  - Delivered: all suites (252 tests), native app and CLI builds, and a native
    planner/inspector preview with fictional data (`PROJECT.md` at commit `8879f0a`).
  - **Open:** a native reservation/apply cycle. v0.2.0 recorded it as
    additional verification; widget tests cover the reservation path.
- [x] Set app/CLI version0.2.0, update contracts/status/setup with official
  references, build/mount/signature/checksum-verify universal DMG.
  Evidence: commit `7b75532`; tag `v0.2.0`.
- [x] Integrate tested source, push private main/tag and publish v0.2.0 DMG plus
  SHA-256. Verify GitHub uploaded size/digest. Keep v0.1.0 intact.
  Evidence: commit `8879f0a` (verified private v0.2.0 release assets).

## Verified references

- OCI sizes/IPv4 reserves and unresolved IPv6 policy:
  https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ipv6.htm and
  https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm
- Growth/contiguous addressing policy:
  https://docs.oracle.com/en/solutions/oci-best-practices/define-your-network-and-connectivity-architecture1.html
- Flutter pan/zoom: https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html
- All existing release script flags were verified against installed macOS/GitHub
  help for v0.1.0; recheck any newly introduced flags before use.
