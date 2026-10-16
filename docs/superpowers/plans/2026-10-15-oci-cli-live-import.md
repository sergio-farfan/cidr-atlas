# OCI CLI Live Import Implementation Plan

Author: Sergio Farfan <sergio.farfan@gmail.com>

Delivery method: Independent workstreams with code review and integrated validation.

**Goal:** Add explicit, read-only OCI discovery with profile/region/compartment selection, preview, and atomic local import in the app and desktop CLI.

**Architecture:** A new pure Dart `cidr_oci` package returns an OCI JSON bundle. Existing `cidr_data` preview/reconciliation/transactions retain authority over writes. UI and CLI share this adapter; neither reimplements OCI collection.

**Tech Stack:** Flutter 3.47.7, Dart 3.13.5, SQLite, installed OCI CLI 3.94.1, package:test and flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-15-oci-cli-live-import-design.md` (approved 2026-10-15).

## Global Constraints

- Keep the existing Flutter UI, pure Dart engine, and local SQLite architecture.
- Collect VCNs and subnets for one explicitly selected region and compartment per run.
- A routing domain is required separately, because tenancy and compartment do not define connectivity.
- Neither shared package imports Flutter.
- Each subprocess uses an executable plus an argument list with `runInShell: false`.
- Preserve `ImportPreview.source == 'OCI JSON'` and incoming record source `oci`.
- Never infer that omitted resources are free; retain real discovered overlaps for review.
- No credentials, customer inventories, generated builds, or machine-specific SDK paths in Git.
- Sergio Farfan is the sole author; commits use `Sergio Farfan <sergio.farfan@gmail.com>`.
- Project-owned code files use professional purpose/author headers with `Sergio Farfan <sergio.farfan@gmail.com>`; code and documentation contain no assistant attribution or activity notes.
- No automatic login, silent tool installation, or live collection in automated tests.

## Review Focus

- Finder's PATH can omit Homebrew: standard macOS OCI locations and explicit override must work (Task 1 test).
- OCI rc/env defaults can change scope or output: child arguments/environment must prevent this (Task 1 test).
- DEFAULT inheritance and token profiles must not expose secret values or choose the wrong authentication mode (Task 1 test).
- A dialog dismissed during discovery must cancel the child and ignore late completion (Task 3 test).
- A failed second resource list must not allow a partially successful first list to reach apply (Tasks 1 and 4 tests).

## Shared adapter interface

Task 1 defines these public types in `package:cidr_oci/cidr_oci.dart`; other tasks consume them verbatim. Immutable value types use named constructors/fields as listed.

```dart
enum OciAuthMode { apiKey, securityToken }
class OciProfile { // const named constructor
  final String name, tenancyId, region;
  final OciAuthMode authMode;
}
class OciConnection { // const named constructor
  final String executable, configFile, profile, tenancyId;
  final OciAuthMode authMode;
}
class OciRegion { // const named constructor
  final String name, status;
  final bool isHome; // default false
}
class OciCompartment { // const named constructor
  final String id, name;
}
class OciDiscovery { // const named constructor
  final String bundleJson;
  final List<String> warnings; // default const []
}
class OciCancellation {
  bool get isCancelled;
  void cancel();
}
abstract interface class OciInventoryClient {
  Future<List<OciProfile>> profiles({String? configFile});
  Future<OciConnection> connection({required String profile,
    String? configFile, String? executable, OciAuthMode? authMode});
  Future<List<OciRegion>> regions(OciConnection connection,
    {OciCancellation? cancellation});
  Future<List<OciCompartment>> compartments(OciConnection connection,
    {required String region, OciCancellation? cancellation});
  Future<OciDiscovery> discover(OciConnection connection,
    {required String region, required String compartmentId,
    OciCancellation? cancellation, void Function(String)? onProgress});
}
class OciCliClient implements OciInventoryClient { // zero-argument default constructor
  // Optional injectable runner/environment/clock/timeouts are Task 1's choice.
}
class OciException implements Exception {
  final String message; // safe, actionable text; no raw credential output
}
```

Cancellation and collection failures throw `OciException` with safe messages; no partial OciDiscovery is returned. No source relabeling is performed by the adapter. Keep diagnostics out of JSON record source fields. Task 1 owns constructor details not fixed above and documents them before consumers use them.

### Task 1: Shared OCI adapter and process lifecycle

**Files:** Create `packages/cidr_oci/pubspec.yaml`, lockfile, `lib/cidr_oci.dart`, focused files in `lib/src/`, and tests in `test/`.

**Interfaces:** Produces the shared interface above. Consumes dart:io/convert/async, without cidr_data/Flutter. Model and command references are in the spec.

- [x] Write failing tests for profiles/DEFAULT inheritance/API-key versus token auth, secret omission, executable discovery, safe missing-tool errors, and malformed config.
- [x] Run tests and confirm expected missing behavior, then implement allowlisted metadata parsing and connection resolution; never read key/token files.
- [x] Write failing collector tests asserting exact explicit connection flags, empty rc isolation, all-page selected-compartment VCN/subnet calls, safe OCI environment, READY region parsing, accessible compartments plus synthetic root, and no unwanted recursive resource collection.
- [x] Implement process execution with concurrent stream consumption, closed stdin, bounded CLI retries, per-command 60-second and collection 180-second deadlines, and cancellation that terminates/drains a process. Verify timeout/cancellation using a controlled real child as well as injected fixtures. Validate any CLI flags against installed help before use.
- [x] Test complete bundle metadata/interval/coverage, external VCN deduplication, denied/not-found context warnings, required-list failure, malformed output, and cancellation without partial results. Implement only the verified read-only command set.
- [x] Run package format/analyze/full test suite. Self-review and report exact red/green evidence. Commit only owned package files after coordinating the shared index.

### Task 2: Preserve all current OCI CIDR aliases

**Files:** Modify `packages/cidr_data/lib/src/import.dart`; tests in `packages/cidr_data/test/import_test.dart` and/or `store_test.dart`.

**Interfaces:** Existing InventoryImport/Store API remains unchanged. Consumed by Tasks 3/4 through the existing OCI JSON source contract.

- [x] Add failing tests for subnet `ipv4-cidr-blocks`/`ipv4CidrBlocks` and VCN `byoipv6-cidr-blocks`/`byoipv6CidrBlocks`, including legacy alias duplicates and shared resource identity.
- [x] Run targeted tests and confirm missing prefix assertions fail. Extend the existing normalizer's deduplicated union; do not change hierarchy or conflict rules.
- [x] Test an OCI refresh carrying the added fields still preserves planning metadata and absent resources, and structurally invalid data still rolls back atomically.
- [x] Run package format/analyze/full tests. Commit only owned data files after coordinated review; report evidence.

### Task 3: Native OCI discovery and shared import preview

**Files:** Create `apps/cidr_atlas/lib/oci_dialog.dart` and `test/oci_dialog_test.dart`; modify `lib/dialogs.dart`, app pubspec/lockfile, and existing tests only if needed.

**Interfaces:** Consumes OciInventoryClient above. `OciDiscoveryDialog({OciInventoryClient? client, String? domain})` returns `OciImportSelection(bundleJson, routingDomain)`. `ImportDialog` gains optional `OciInventoryClient? ociClient` for real-client default/test injection. Existing offline callers remain valid.

- [x] Add failing widget tests for entry from ImportDialog, metadata-only profile load, selecting auth/profile, explicit Load scopes, READY region selection/manual scope fallback, and required routing domain.
- [x] Add the dialog and OCI entry without adding a toolbar action. Use existing visual styles, bounded dropdown text, wrapping controls, and scrolling at both supported widths. Do not auto-call OCI network APIs on startup.
- [x] Test progress, Cancel/dispose cancellation, late results ignored, and collection errors with Apply unavailable; implement lifecycle behavior.
- [x] Return bundle/domain to ImportDialog and feed its current `_parse` path using `InventoryImport.json`; retain proposedRecords/mergedImportRecords, errors/conflicts/warnings, and atomic existing Apply behavior. Test preview-only/cancel leaves an in-memory store unchanged and Apply imports only when valid.
- [x] Run format on owned Dart files, Flutter analyze, and full widget tests at 1100×740/1440×900. Commit owned files after coordinated review and report evidence.

### Task 4: Desktop discovery CLI

**Files:** Modify `packages/cidr_cli/lib/cidr_cli.dart`, `bin/cidrctl.dart`, pubspec/lockfile; create `test/discovery_test.dart`.

**Interfaces:** Preserve synchronous `runCidrctl` for existing callers. Add `Future<int> runCidrctlAsync(List<String>, {StringSink? out, StringSink? err, Map<String,String>? environment, OciInventoryClient? ociClient})`; entrypoint awaits it. Existing commands delegate unchanged; new discovery uses the shared client.

- [x] Write failing tests for `discover oci` help/required flags (`--profile`, `--region`, `--compartment-id`, `--routing-domain`), overrides (`--config-file`, `--oci-bin`, `--auth api_key|security_token`), and default preview versus explicit `--apply`.
- [x] Implement async discovery dispatch, safe errors, progress to stderr, bundle-to-InventoryImport.json, merged preview and atomic apply; no separately persisted raw OCI dump.
- [x] Test required-list failure/cancellation without inventory/history changes, metadata preservation, domain isolation, absent-resource retention, conflicts remain visible, and valid/invalid apply. Keep exit 0 success/preview, 1 operation/import failure, 2 usage error; manual reserve still uses 3 for conflict.
- [x] Run format/analyze/full CLI tests, compile native CLI, and smoke with a controlled fictional OCI executable against a temporary DB. Commit owned CLI files after coordinated review; report evidence.

### Task 5: Integrated verification, documentation, and private repository

**Files:** Update README.md, PROJECT.md, docs/CONTRACT.md, docs/architecture.md, scripts/build_dmg.sh, and this plan's checkboxes with actual outcomes. No invented live verification.

**Interfaces:** Consumes completed Tasks 1–4, existing build scripts, GitHub identity `sergio-farfan`.

- [x] Review each task's spec compliance and code quality with an independent task reviewer and resolve material findings. Review the whole integrated branch afterward.
- [x] Run all shared-package analyzers/tests and Flutter analyzer/widget suite; build native app/CLI. Native smoke uses fictional profiles/executables until the user chooses a real connection and scope. Do not claim live OCI/IAM success from fixtures.
- [x] Document setup, exact compartment scope, authentication choices, CIDR aliases, preview/apply, coverage, and failure behavior with official citations. Update handoff and checks precisely.
- [x] Build and verify a universal macOS DMG, mounted app contents/signatures, and SHA-256 checksum.
- [x] Publish the verified DMG and checksum in the private repository's Releases. The v0.1.0 preview is published; uploaded asset sizes and SHA-256 digests were verified.
- [x] Verify private GitHub repository ownership/visibility and push the tested source under Sergio Farfan authorship. Keep credential/config files, real observations, SDK locations, and generated outputs excluded.
- [x] Finish with artifact/repository links, test/build evidence, actual live-verification limits, and a useful next action in README.md and PROJECT.md.
