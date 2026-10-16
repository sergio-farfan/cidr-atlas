# CIDR Atlas — Expanded OCI discovery implementation plan

Author: Sergio Farfan <sergio.farfan@gmail.com>

**Goal:** Collect selected/all READY regions and all accessible compartments into
one safe preview, improve planner space use, and deliver a verified macOS release.

**Architecture:** Flutter and CLI share the pure Dart OCI collector. Existing
JSON import and SQLite transactions retain ownership of validation and apply.

**Specification:** [Expanded OCI discovery](../design/2026-10-15-expanded-oci-discovery.md)

## Constraints and review focus

Preserve sole authorship, offline imports, strict region identities, domain-scoped
conflicts, cancellation and fail-closed required calls. Test late failure rather
than merely happy-path aggregation, duplicate scopes, empty READY selection,
regional context lookup, cross-region apply/refresh, and small-window layout.

## Task 1: Shared collector

Files: packages/cidr_oci/lib/src/client.dart and owning tests.

- [x] Add failing tests for all scope combinations, duplicate regions/compartments,
  non-READY/zero READY regions, late failure, region stamping, context dedup,
  deadlines and cancellation. Adapt current single-region tests to list input.
- [x] Implement the exact discover API and bounded sequential matrix from the spec.
- [x] Run cidr_oci tests and analyzer; record evidence and commit the collector.

## Task 2: Discovery interfaces

Files: apps/cidr_atlas/lib/oci_dialog.dart, dialogs.dart, help.dart and tests;
packages/cidr_cli/lib/cidr_cli.dart and discovery tests.

- [x] Add failing scope UI/CLI tests including mutual exclusion, multiple selected
  regions, broad empty guidance, busy controls and no partial persistence.
- [x] Wire exact collector inputs, retain manual fallback and one atomic preview.
- [x] Add help/examples for all four combinations and clear IAM coverage guidance.
- [x] Run CLI and Flutter tests/analyzers; record evidence and commit interfaces.

## Task 3: Planner and integration

Files: apps/cidr_atlas/lib/visual_planner.dart and tests;
packages/cidr_data/test; docs/CONTRACT.md, architecture.md, user-guide.md, README.md,
PROJECT.md and package version references.

- [x] Inspect current constraints and make compact responsive map-first layout;
  add meaningful width/scroll tests and retain reservation calculations.
- [x] Test combined multi-region import, parent identities, atomic apply and repeat
  refresh retaining local fields/absent records using fictional fixtures.
- [x] Update contracts, guidance and version to 0.3.0; verify all affected packages.
- [x] Obtain fresh independent whole-change review and address material findings.
- [x] Freeze source, clean build universal macOS app and CLI, verify DMG/signature.
- [ ] Publish private v0.3.0 prerelease and remotely verify both asset digests.
- [ ] Record actual publication in PROJECT.md and keep primary clean.
