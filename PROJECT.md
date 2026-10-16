# CIDR Atlas — implementation status

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Product direction

Local-first CIDR inventory and allocation planning for cloud/network administrators.
The macOS Flutter app and desktop CLI share pure Dart network rules, OCI discovery,
and a local SQLite inventory. Offline CSV/JSON imports remain available. iOS,
Windows and Linux graphical releases and team synchronization are future work.
New installations start empty; optional demo inventories are fictional.

## Current implementation

The last published release is v0.3.0 (see Release status). The working tree
also holds an unreleased review remediation, recorded in
[the remediation plan](docs/plans/2026-10-16-review-remediation.md), and the
inventory-clearing and discovery-progress changes listed below. No release has
been published from it; the app and CLI are versioned 0.4.0.

The v0.3.0 implementation adds one/several selected regions or all READY subscribed
regions, independently paired with one direct compartment or all accessible active
compartments and subcompartments, including tenancy root. It collects all resource
pages for each region/compartment pair into one preview. Every resource retains its
actual region and compartment; refresh preserves planning metadata and absent
records. Accessible compartment visibility does not guarantee network-list access
or visibility of IAM-hidden resources. Required failures stop collection without
an applicable partial bundle. Offline imports, preview and atomic apply are retained.

The planner uses compact planning controls beside the main address map, with an
adjacent selected-network inspector when width permits. It shows address hierarchy,
OCI VCN membership, conflicts, blocked/free space, exact slot totals and bounded
recommendations. Address containment does not establish connectivity. A topology
view needs observed routes, gateways, DRGs, peering and security resources; those
remain a separate collection/storage milestone.

The shared CIDR inspector shows prefix/host bits, IPv4 mask, network and address
range, exact counts, theoretical child slots and a selected containing supernet.
OCI IPv4 subnet capacity supports /16 through /30 with three reserved addresses.
Demand sizing requires explicit growth and separate additional demand. IPv6 uses
exact integers without inventing an OCI assignable-host policy. Availability is
conditional on inventory coverage and the explicit routing domain.

Local reservations recheck identity, structure and current conflicts in the SQLite
write transaction. Imported conflicts remain reviewable. Refresh retains local
owner, notes, status, parent, environment and customer fields and never deletes or
retires omitted resources. Source observation time remains distinct from apply time.

Offline Help and examples and the [user guide](docs/user-guide.md) explain scope
selection, empty results, manual CIDRs, planning prefixes, capacity and routing
domains with fictional copyable examples. Empty live results keep Apply disabled;
validation errors remain visible without duplicates. Coverage is expandable.

Unreleased remediation, by package (details in `docs/CONTRACT.md`):

- **Core:** conflict detection is a sorted sweep, O(n log n + overlapping pairs),
  with unchanged results and ordering; `conflictsFor` checks changed records only.
  A subnet whose explicit parent is a placeholder VCN while its VCN OCID names a
  comparable VCN recorded elsewhere is reported by the non-blocking
  `InventoryRules.advisories` (name, CIDR and OCID of the recorded VCN, the
  placeholder parent, and "clear or change the parent"); the link stays valid as
  in v0.3.0, so such inventories remain writable and an OCI refresh that brings
  in the real VCN applies. `parseObservationTime` is the strict timestamp parser;
  `tryParseStoredTimestamp` is exported for stored and legacy values; records
  write `verifiedAt` in UTC. Prefix lengths with leading
  zeros are rejected, and planning reports a malformed blocker by record ID.
- **Data:** id-matched CSV rows merge only the columns supplied; id-less row
  collisions are row-numbered errors, with a warning when an id-less row replaces a
  differently named record. OCI previews warn about retired records still observed
  live, bundles older than existing observations and truncated raw CLI pages. CSV
  export guards formula cells with a lossless round trip. CSV and backup
  `verifiedAt` reject calendar rollover; the zone-less form v0.3.0 exported is read
  as local time with a counting preview warning, so v0.3.0 backups and CSV exports
  restore. OCI refresh matches records by OCID regardless of region spelling, so
  records v0.3.0 stored under `IAD` or an uppercase region are updated in place,
  keep their planning fields and take the canonical region (also carried to an
  unobserved linked VCN or subnet). Previews list advisories as warnings. Deleting a parent with children is refused
  with an explanation; `deleteAll` removes several records in one transaction.
  `defaultDatabasePath` is shared by the CLI and app. Rollback errors no longer
  mask the original failure.
- **OCI adapter:** regions are canonicalized (three-letter keys resolved through
  subscriptions) before deduplication; compartments carry parent OCIDs and display
  paths. Requests use 10 s connect and 15 s read timeouts with `--max-retries 3`
  (three attempts in OCI CLI 3.94.1) and a 120 s command bound. Structured
  `OciDiscoveryProgress` reports scope count and the limit in effect. The profile
  parser follows ConfigParser; `~/` and `$HOME/bin/oci` executable lookup added.
- **CLI:** `export --file` refuses the open database and replaces other files
  atomically, keeping their mode. `reserve` writes through the store's strict
  reservation path and prints placeholder-parent advisories on stderr;
  `recommend --apply` with no candidate prints `No reservation was saved.` instead
  of the preview hint. New stderr warnings for a newly created empty database and an
  unused routing domain; an empty live discovery exits 0; the database path is
  checked before OCI collection; `--collection-timeout` added; the configuration
  file and profile used are printed. Several usage errors now exit 2 consistently.
- **App:** shared default database path (macOS path unchanged), Planner input
  validation messages, cached planner hierarchy, address-axis zoom with **Zoom to
  candidate**, compartment paths, editor errors kept inline, read-only observed
  OCI fields, a non-blocking placeholder-parent notice in the record editor,
  labeled and removable sample data, history paging, an optional
  discovery time limit, and screen-reader semantics for candidates, errors and
  progress.
- **Clear inventory:** **Clear inventory…** in the inventory table header deletes
  every local record or one routing domain after the user types `CLEAR`, with
  **Export backup first**, one transaction and one history entry; a count changed
  by `cidrctl` meanwhile deletes nothing. `cidrctl clear [--routing-domain D]
  --yes` does the same from the CLI, requires `--yes` (exit 2 otherwise) and
  never creates a missing database (exit 1). OCI is never touched.
- **Discovery usability:** a modal progress panel centred over the discovery
  dialog (step, scope progress bar, elapsed time, collection limit, its own
  Cancel) replaces the in-form indicator that could sit below the visible area;
  later errors scroll into view. A hint flags tenancy root as the direct
  compartment, and an empty direct-compartment result offers **Retry with all
  accessible compartments**, which reruns discovery at once with the same
  profile, settings, regions and routing domain.
- **Hygiene:** consistent lint configuration in every package
  (`package:lints/recommended.yaml`; `flutter_lints` for the app), missing file
  headers, `scripts/cidrctl` dependency freshness, DMG staging under `build/`,
  unused `path_provider`/`path` app dependencies removed, and `~/tmp` examples.

## OCI collection contract

The shared adapter uses an existing local OCI CLI/profile; private-key and token
access stays within the CLI. Metadata selection is explicit, as are network
requests. There is no automatic sign-in, provisioning, background collection or
credential creation. Requests use explicit profile/config/auth/region/JSON,
isolated rc/environment defaults and all pages. Without an explicit configuration
file, `OCI_CLI_CONFIG_FILE` (when set) or `~/.oci/config` is used.

Collection is sequential with progress, cancellation and safe operation/scope
errors. In the remediated tree each request passes `--connection-timeout 10`,
`--read-timeout 15` and `--max-retries 3`, and each command is bounded to 120
seconds (v0.3.0: 60 seconds and `--max-retries 1`, which in OCI CLI 3.94.1 meant a
single attempt). Whole collection defaults to 180 seconds for one selected pair
and 1800 seconds for broader modes, adjustable through `--collection-timeout` or
the discovery dialog. A required failure returns no bundle. Denied/not-found
referenced VCN context remains a warning; context queries use the actual region.
Coverage records modes, actual regions/compartments, completed scopes/resource
counts, observation interval and context outcomes. It is not a complete or
transactionally consistent tenancy audit.

Validated against installed OCI CLI 3.94.1 and Oracle's
[compartment list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html),
[region subscriptions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html),
[VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html),
[subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html)
and [VCN get](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html).
Root-only subtree enumeration uses ACCESSIBLE and ACTIVE, adding root once.
Only READY subscriptions are included in all-region mode. A successful blank CLI
list is accepted only for known list commands, consistent with Oracle's
[3.94.1 CLI renderer](https://github.com/oracle/oci-cli/blob/v3.94.1/src/oci_cli/cli_util.py#L893-L947);
empty object gets remain invalid. The retry and timeout semantics come from the
installed CLI's `--help` and its SDK source, not from a run against a tenancy.

## Verification

Toolchain: macOS 26.7.1 Apple Silicon, Xcode 27.0 (27A266a), Flutter 3.47.7,
Dart 3.13.5, OCI CLI 3.94.1. Native dependencies use Swift Package Manager.
Machine-specific SDK paths are not tracked.

Unreleased remediation, verified 2026-10-16 on the working tree:

- Core: 72 tests passed (v0.3.0: 50).
- Data/imports: 124 tests passed (v0.3.0: 78).
- OCI adapter: 110 tests passed (v0.3.0: 83; before the remediation this machine
  ran 82 plus one failure that depended on `PUB_CACHE` being set, now fixed).
- CLI: 98 tests passed (v0.3.0: 49), rerun after adding `clear`.
- Flutter: 130 widget tests passed (v0.3.0: 72), rerun after adding clear
  inventory, the progress panel and the all-compartments retry.

All 534 package/widget tests passed (core, data and OCI adapter counts are from
the remediation run; those packages are unchanged since). `dart format --set-exit-if-changed` changed no
files in any package, and `dart analyze` / `flutter analyze` reported no issues
under the stricter lint configuration. Tests use fictional runners, isolated
temporary or memory stores and a fictional `HOME`; no live tenancy was collected,
no OCI configuration was read and the default inventory was not opened. A string
comparison on this Mac during the remediation confirmed that the shared default path equals the v0.3.0
app path. The Windows branches of path canonicalization and default paths have
not been run.

Native 0.4.0 build (unpublished): a clean release build of the app (0.4.0, build
5, arm64 and x86_64, ad hoc signed, strict deep signature verification) and the
`cidrctl` executable were built on Apple Silicon from the tree that includes the
clear-inventory and discovery-progress changes. `build_dmg.sh --skip-build`
produced `CIDR-Atlas-0.4.0.dmg`, its SHA-256 file and the identical stable-name
`CIDR-Atlas.dmg`, passing both architecture checks, signature integrity, image
verification, read-only mounting, contents and checksum. An end-to-end run of the
compiled CLI on scratch databases (94 checks) found two gaps, both fixed and
re-checked on the rebuilt binary. A copy of a v0.3.0 inventory read, listed and
round-tripped through backup and restore with identical records, and launching the
app left the original database unchanged. The new dialogs (centred progress panel,
Clear inventory, all-compartments retry) are covered by widget tests; hands-on
native checks of them are outstanding.

v0.3.0 release verification (the last published release):

- Core: 50 tests passed; analyzer clean.
- Data/imports: 78 tests passed; analyzer clean. New fictional multi-region tests
  verify regional identities and parents, atomic apply, repeat refresh retaining
  local fields/absent regions, rollback for an invalid later record, and visible
  same-domain overlap across regions.
- OCI adapter: 83 tests passed; analyzer clean, including all scope combinations,
  root/region deduplication, pagination, regional context, READY exclusions, empty
  results, late required failures, cancellation and single/broad deadlines.
- CLI: 49 tests passed; analyzer clean, including pre-connection scope validation,
  repeated/comma-separated regions, all-scope flags, help and no partial writes.
- Flutter: 72 widget tests passed; analyzer clean, including GUI scope combinations,
  busy controls, broad empty retry, copyable help and responsive planner/reservation.

All 332 package/widget tests passed. The planner's 390/780/1100/1440 pixel widget
layouts retain controls and reservation access; wide views put the map above the
fold. Current validation uses fictional runners and isolated temporary/memory
stores; it does not collect a live tenancy or change the user's default inventory.
Independent whole-change and scoped layout reviews found no actionable issues.
The compiled CLI passed isolated fictional end-to-end checks for all four scope
combinations, preview without record/history writes, 12-record multi-region apply,
and a late permission failure retaining exact records/history and withholding raw
CLI diagnostics. Native QA verified scope toggles and fictional planning; resizing
identified and corrected the compact-desktop breakpoint. The final clean native release app built at 45.1 MB for arm64/x86_64. The final
DMG passed both architecture checks, deep/strict code-signature integrity, image
verification, read-only mounting, expected-content inspection, detach and checksum
validation. The corrected native build launched with the retained local inventory. Inventory/audit fingerprints remained equal
after launch, navigation, planning preview and scope selection; no live resource
requests or local inventory writes were performed during native QA.

## Release status

The private [v0.3.0 preview release](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.3.0)
is published with its universal DMG and checksum. Both uploaded asset sizes and
SHA-256 digests match the verified local artifacts; private repository visibility
and the unchanged v0.2.1 DMG were rechecked. Tag `v0.3.0` identifies source commit
`e2318076b56536565834a7f480764b1d5f6f85be`. The DMG is
21,157,660 bytes; SHA-256 is
`91090df278ce252f05db2119464fb4efac20eb5d23a590463ed433458b078cc7`.
The checksum-file SHA-256 is
`0fc42df546b22afdb49c4c56065cbda91ca36763ff6433f3a37f0e567be0ef5a`.

The prior published preview is [v0.2.1](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.1).
Its universal DMG is 21,024,500 bytes, SHA-256
`bf8818d8364ad3cfffd5b8de44cc1b726b99b195a3e339c4f4a1615d2df8ece8`.
The [v0.2.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.0)
and [v0.1.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0)
assets are preserved.

`scripts/build_macos.sh`, `build_cli.sh` and `build_dmg.sh` build the universal app,
current-platform CLI and verified DMG. Packaging checks both architectures,
deep/strict signature integrity, read-only mounted contents and SHA-256.
Signing is ad hoc; no Developer ID signature or notarization ticket exists. Local
verification does not establish Gatekeeper acceptance on another Mac. The app has
App Sandbox disabled for local CLI process access and shared app/CLI storage.

`cidr_core`, `cidr_data` and `cidr_oci` remain 0.1.0; `cidr_cli` is 0.4.0 and
the app is 0.4.0+5, neither yet released. `cidrctl --version` comes
from a constant in `packages/cidr_cli/lib/cidr_cli.dart`; a test now ties it to
the CLI pubspec. The declared SDK floors (>=3.4.0 for core and OCI, >=3.5.0 for
data and CLI) are lower than the lockfiles resolve (>=3.11.0); raising them to
>=3.11.0 was tried in a scratch copy and deferred, because it switches
`dart format` to the tall style and would reformat about 37 files.

## Next actions

Check the centred progress panel, Clear inventory and the all-compartments retry
in the native 0.4.0 build, then publish 0.4.0 following
[docs/releasing.md](docs/releasing.md). Add the light/dark/system theme setting. Decisions recorded in the remediation plan:

- All-compartments mode: continue past a compartment that denies network listing
  and record it as unobserved coverage, instead of failing the whole collection
  (changes the documented fail-closed contract; #19).
- Strict variants: require `--force` to overwrite an existing export file (#0);
  read-only commands refuse a nonexistent database instead of warning (#9);
  case-insensitive routing-domain identity (#45).
- Release provenance (clean-tree check, source commit in the DMG; #56), a CI
  workflow (#57), a platform gate for OCI discovery on iOS (#63), and blocker
  attribution, per-status map patterns and planner view filters (#64).
- Broad-mode collection strategy (bounded concurrency or a Search pre-filter)
  beyond the timeout option.
- SDK floors and package version alignment (#53): raise the floors together with
  a one-time tall-style reformat, and decide whether library packages follow the
  release version.
- Follow-ups from the remediation: JSON backup records with missing keys merge
  rather than replace (#1); a writability probe for an existing but unwritable
  database directory before collection (#37); lazy rendering of very large
  planner hierarchies (#5); an `Export all` widget test (#7); a process-level
  SIGINT test for `discover` (#40); an iOS branch in `defaultDatabasePath` before
  an iOS app uses it; a refresh-without-change that keeps planner results; a
  repair path for inventories that already hold two copies of one OCID/CIDR under
  different region spellings (such a refresh now stops with "Multiple existing
  records match"); one intermittent `cidr_oci` failure observed once in 13 full
  runs and not reproduced under load, so harden the real-process timing tests.
- IPAM roadmap: prioritize from the Infoblox comparison in
  `docs/design/2026-10-16-ipam-feature-assessment.md` (Tier 1 items need no record
  model change).

Scope the observed connectivity collector and topology model while retaining
address inventory and allocation as the main workflows. Wider distribution
requires Developer ID signing and notarization. Keep customer data, credentials,
databases, generated builds and machine-specific SDK paths out of Git.
