# CIDR Atlas changelog

Author: Sergio Farfan <sergio.farfan@gmail.com>

All notable changes to CIDR Atlas will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Prepared as 0.4.1 (app 0.4.1+6, `cidrctl` 0.4.1).

### Added

- Homebrew install channel: `brew install --cask sergio-farfan/tap/cidr-atlas` installs the app and links `cidrctl` for the Mac's architecture; `--zap` removes the preferences and keeps the inventory.
- The disk image carries `cidrctl-arm64` and `cidrctl-x86_64`, one per architecture, with installation steps in `INSTALL.txt`. `scripts/build_cli.sh --both` builds them (the Intel one with a matching x64 Dart SDK under Rosetta), and `build_dmg.sh` checks each one's architecture, signature and version.

### Changed

- The repository is public: version and download badges, private vulnerability reporting through GitHub Security Advisories, and the macOS app CI job runs on pull requests.

- iOS is dropped as a target for now. macOS stays the only graphical release; Windows and Linux remain later milestones, and the shared engine stays portable Dart. The project has no iOS platform directory, and the previously planned iOS items (a discovery platform gate and an iOS branch in `defaultDatabasePath`) are retired.

## [0.4.0] - 2026-10-16

App 0.4.0 (build 5) and `cidrctl` 0.4.0. Inventories, JSON backups, CSV exports and the macOS database path from v0.3.0 remain compatible.

### Added

- **Settings** (gear icon in the workspace header, **CIDR Atlas > Settings…** or ⌘,) with an **Appearance** choice of **System**, **Light** or **Dark**. System, the default, follows the macOS appearance; the choice applies immediately and is kept in the app's user defaults (`theme.appearance`), outside the inventory. A new light theme meets WCAG AA text contrast; the dark theme keeps the existing look. Adds the `shared_preferences` package.
- **Clear inventory…** in the inventory table header deletes every local record, or one routing domain, after the user types `CLEAR`. It offers **Export backup first**, runs in one transaction with one history entry, keeps change history and never touches OCI. If `cidrctl` changes the record count in the meantime, nothing is deleted.
- `cidrctl clear [--routing-domain D] --yes` does the same from the CLI. Without `--yes` it exits 2 and changes nothing; a missing database exits 1 and is never created; a record in another routing domain that names a cleared record as its parent blocks the clear.
- A progress panel centred over the discovery dialog shows the step, completed region/compartment scopes, elapsed time, the collection limit and its own **Cancel**. It replaces the in-form indicator that could sit below the visible area; later errors scroll into view.
- An empty direct-compartment discovery offers **Retry with all accessible compartments**, which reruns discovery at once with the same profile, settings, regions and routing domain, including subcompartments.
- A hint when tenancy root is the direct compartment, noting that root usually holds no networks and that children require the all-compartments option.
- `cidrctl discover oci --collection-timeout SECONDS` (30 to 86400) and an optional **Collection time limit, minutes** field (1 to 1440) in the discovery dialog for large scopes.
- Discovery progress reports the scope count and the limit in effect; the CLI prints the configuration file and profile used.
- Compartments are listed by their path from tenancy root, with the selected OCID shown below the selector.
- Import previews warn about locally retired records still observed live, bundles older than existing observations, truncated raw OCI CLI pages and non-blocking parent advisories.
- CLI stderr warnings for a newly created empty database and for a routing domain with no records, naming case-insensitive near matches.
- Planner address-axis zoom with **Zoom to candidate**, history paging and screen-reader semantics for candidates, errors and progress.
- Fictional sample data is labeled with source `demo` and can be removed in one change with **Remove sample data**.

### Changed

- OCI CLI requests use a 10 s connection timeout, a 15 s read timeout and `--max-retries 3` (three attempts in OCI CLI 3.94.1), with a 120 s bound per command. v0.3.0 used 60 s and `--max-retries 1`, which meant a single attempt.
- Regions are canonicalized before deduplication: full identifiers in any case, or three-letter keys such as `IAD` resolved through the tenancy's region subscriptions. Other forms are rejected before any request.
- OCI refresh matches existing records by OCID regardless of region spelling, so records v0.3.0 stored under `IAD` or an uppercase region are updated in place, keep their planning fields and take the canonical region.
- A successful discovery that finds no networks exits 0 with a neutral message.
- `cidrctl reserve` writes through the store's transactional reservation path, which rechecks identity, structure and conflicts inside the write transaction.
- `cidrctl export --file` refuses the open database and its SQLite companion files, and replaces other files atomically, keeping their mode.
- The database path is checked before any OCI collection starts.
- Conflict detection is a sorted sweep, O(n log n + overlapping pairs), with unchanged results and ordering; writes check only the changed records.
- A subnet whose explicit parent is a placeholder VCN while its VCN OCID names a comparable recorded VCN is reported as a non-blocking advisory, so such inventories stay writable.
- Observed OCI fields are read-only in the record editor; editor errors stay inline and keep the form input.
- The CLI and app share one default database path rule; the macOS path is unchanged from v0.3.0.
- Several usage errors now exit 2 consistently. `recommend --apply` with no candidate prints `No reservation was saved.`

### Fixed

- CSV rows matched by ID now merge only the columns supplied, instead of erasing omitted fields.
- CSV rows without an ID that collide are reported as row-numbered errors, with a warning when such a row replaces a differently named record.
- CSV export escapes formula cells with a lossless round trip.
- CSV and backup `verifiedAt` values reject calendar rollover; the zone-less form v0.3.0 exported is read as local time with a counting preview warning, so v0.3.0 backups and CSV exports restore.
- Prefix lengths with leading zeros (such as `/08`) are rejected.
- Planner input errors show validation messages instead of raw exceptions.
- Deleting a parent that still has children is refused with an explanation.
- A rollback error no longer masks the original failure.
- The OCI profile parser follows ConfigParser behavior (header trailing comments, indented continuation lines); `~` is expanded for an explicit executable and `$HOME/bin/oci` is a lookup candidate.
- Export through a `..` segment to a missing SQLite companion file, and discovery against a file that is not a SQLite database, are refused before any write or OCI request.

### Validation

- Verified 2026-10-16 on the working tree: core 72, data 124, OCI adapter 110, CLI 98 and Flutter widget 176 tests passed (580 total; v0.3.0: 332). `dart format --set-exit-if-changed` changed no files, and `dart analyze` / `flutter analyze` reported no issues under the stricter lint configuration.
- Tests use fictional runners, isolated temporary or memory stores and a fictional `HOME`. No live tenancy was collected, no OCI configuration was read and the default inventory was not opened. The retry and timeout semantics come from the installed OCI CLI 3.94.1 `--help` and SDK source, not from a run against a tenancy.
- An end-to-end check of a compiled 0.4.0 CLI found the two export/discovery gaps listed under Fixed, which are now covered by regression tests.
- Native build: a clean universal release app (arm64 and x86_64, ad hoc signed, strict signature verification), the `cidrctl` executable and the DMG were built on Apple Silicon; the DMG passed architecture, signature, image, read-only mount, contents and checksum checks. The compiled CLI passed an end-to-end run on scratch databases after two fixes, and a v0.3.0 inventory copy round-tripped with identical records.
- Not verified: hands-on native checks of the centred progress panel, Clear inventory and the all-compartments retry (covered by widget tests only). The Windows branches of path canonicalization and default paths have not been run. No Developer ID signature or notarization exists.

### Documentation

- Consistent lint configuration in every package (`package:lints/recommended.yaml`, `flutter_lints` for the app), missing file headers added, `scripts/cidrctl` dependency freshness, DMG staging under `build/`, unused app dependencies removed and examples moved to `~/tmp`.
- `docs/CONTRACT.md`, `docs/architecture.md`, `README.md`, `docs/user-guide.md` and `PROJECT.md` synced with the remediation, the new options and the clear command. Added the remediation plan and an Infoblox IPAM feature assessment. The README points at the `~/projects/git/cidr-atlas` checkout location.
- MIT license, changelog, contributing and security policies, issue and pull request templates, CI, and the local release procedure. Release disk images are named `CIDR-Atlas-X.Y.Z.dmg` with a stable-name `CIDR-Atlas.dmg` copy.
- A "Before you start" guide covering the OCI CLI installation, API-key and session-token profiles, the read-only IAM policy statements, and the CSV, JSON backup and OCI JSON import formats with examples.

## [0.3.0] - 2026-10-15

### Added

- Discovery across one or several READY regions, or all READY subscribed regions.
- Independently, one direct compartment or all accessible active compartments and subcompartments, including tenancy root.
- GUI and CLI retain each resource's actual region, report collection progress and coverage, and stop on required failures without an applicable partial inventory.
- Compact planner controls beside the address map, with responsive CIDR details, exact free-slot counts and conflict-aware recommendations.
- Updated offline help and fictional multi-region examples.

### Changed

- The planner map stays beside the controls in compact desktop windows.

### Validation

- 332 package/widget tests passed (core 50, data 78, OCI 83, CLI 49, Flutter 72), with clean analyzers and formatting, independent whole-change and scoped review, isolated compiled-CLI discovery/apply/failure checks, and native planner/scope-control navigation with unchanged inventory and history fingerprints.
- Collector validation used fictional responses rather than a live tenancy-wide audit.
- Universal DMG for Apple Silicon and Intel; packaging verified both architectures, deep/strict signature integrity, image integrity, read-only mounted contents and SHA-256. The standalone CLI was built and verified on Apple Silicon.
- Ad hoc signature, not Developer ID signed or notarized; Gatekeeper acceptance on another Mac is not established.

## [0.2.1] - 2026-10-15

### Added

- Offline Help and examples with copyable fictional CSV, JSON and CLI examples across seven topics. Contextual help opens from Import, OCI discovery and Planner and keeps the current form or preview.

### Changed

- OCI discovery supplies existing network CIDRs automatically; the import preview labels its output as network CIDRs.
- A successful empty discovery shows a neutral completion, explains there is nothing to save and offers another compartment or region; Apply stays disabled.
- Manual record, planning-pool and requested-prefix guidance distinguish a full CIDR such as `10.64.0.0/16` from a requested child size such as `24`.
- Coverage and observation provenance moved to an expandable disclosure. Copied import commands use the required `--file` option.

### Fixed

- Invalid previews no longer repeat the same validation error through merged preview checks.

### Validation

- 61 Flutter widget tests, 74 data-package tests and 45 CLI tests passed; analyzers clean and 46 maintained Dart files passed nonmutating formatting. Copied CSV/JSON examples parsed successfully, and the compiled CLI passed fictional help/import preview/apply checks.
- Native help navigation preserved existing inventory and history. Core and OCI algorithms are unchanged from the verified v0.2.0 baseline.
- Universal DMG passed image, mount, contents, architecture, deep/strict signature and checksum checks. Ad hoc signature, without Developer ID or notarization.

## [0.2.0] - 2026-10-15

### Added

- Visual address planner for an explicit routing domain and allocation or VCN pool, showing allocation hierarchy, grouped OCI VCN prefixes and known subnets, free and blocked space, conflict indicators and ranked recommendations.
- Shared CIDR inspector with exact IPv4/IPv6 totals, mask bits, IPv4 masks, network ranges, child subnet slots and selected containing supernets.
- OCI IPv4 subnet sizing from current/peak demand, an explicit growth percentage and additional demand.
- `cidrctl recommend` for text/JSON previews and explicit apply. GUI and CLI share the same engine and recheck identity, hierarchy and conflicts atomically; saved notes keep the sizing and placement rationale.

### Fixed

- Successful empty OCI CLI lists produce an empty scoped result with compartment guidance instead of a false malformed-response error. Genuine malformed responses identify the failed operation and expected structure without displaying raw resource contents.

### Validation

- 252 tests passed (core 50, data 50, OCI 63, CLI 44, Flutter 45), with clean analyzers and formatting, compiled fictional CLI smoke checks, a native planner preview without inventory/history writes, and independent reviews.
- App built clean for arm64 and x86_64; the DMG passed image verification, read-only mounting, contents, architecture, deep/strict signature and checksum checks. Ad hoc signature, without Developer ID or notarization.
- OCI IPv6 assignable capacity remains unspecified; route, gateway, DRG, security and reachability collection is later work.

## [0.1.0] - 2026-10-15

### Added

- Initial macOS preview for local OCI network address inventory and planning, with a shared pure Dart core, SQLite storage and a desktop CLI.
- VCN and subnet discovery through an existing OCI CLI profile, with explicit authentication, region, compartment and routing domain selection.
- Offline CSV, CIDR Atlas JSON backup and OCI JSON bundle imports through the same preview and atomic apply workflow; subnet IPv4 and VCN BYOIPv6 CIDRs are preserved.
- Refresh keeps local planning metadata and resources absent from the refresh; discovered conflicts remain visible for review.
- Desktop CLI for discovery, import/export, address checks and reservations.

### Validation

- 184 tests passed, all analyzers and format checks passed, the native app and CLI built, and controlled fictional OCI subprocess smoke checks passed.
- The universal DMG (arm64 and x86_64) mounted and passed content, signature-integrity, architecture and checksum checks. Runtime smoke checks ran on Apple Silicon.
- Ad hoc signature, without Developer ID or notarization. Live OCI profile validity and IAM permissions were not verified against an account.

[Unreleased]: https://github.com/sergio-farfan/cidr-atlas/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.4.0
[0.3.0]: https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.3.0
[0.2.1]: https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.1
[0.2.0]: https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.0
[0.1.0]: https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0
