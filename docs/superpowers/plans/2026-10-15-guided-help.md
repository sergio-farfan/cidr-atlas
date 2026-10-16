# Guided Help and Empty Discovery Implementation Plan

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Goal and design

Explain when a CIDR is entered, provide offline in-app guidance and examples,
and distinguish a successful empty OCI discovery from invalid input. Preserve
the Flutter/Dart/SQLite architecture, explicit scope, preview/apply safeguards,
existing CLI behavior, and professional project authorship. Publish v0.2.1 with
a verified universal DMG in the existing private repository.

The import count reports discovered CIDRs; it does not request a manually entered
prefix. Help distinguishes full network CIDR (`10.64.0.0/16`), planning boundary,
and requested child prefix (`24`). Demand mode chooses the latter. Use a neutral
empty-discovery panel with direct-compartment/region guidance, explain disabled
Apply, and offer discovery again. Keep actual malformed/structural errors visible.

## Task 1: Shared help

- Create `apps/cidr_atlas/lib/help.dart` and `test/help_test.dart`.
- Public API: `enum HelpTopic { gettingStarted, imports, ociDiscovery, planning,
  cidrBasics, routingDomains, cli }`; `showAtlasHelp(BuildContext context,
  {HelpTopic topic = HelpTopic.gettingStarted})` returns `Future<void>`;
  `AtlasHelpDialog({super.key, HelpTopic initialTopic = HelpTopic.gettingStarted})`.
- Cover import vs manual/planner input first; OCI profile/authentication, READY
  region/direct compartment, empty results, offline CSV/JSON examples, explicit
  routing domain, canonical CIDRs, demand sizing, aligned slots/coverage, and CLI
  preview/apply examples. Fictional examples only. Include official reference URLs.
- All help is local static content. Use selectable/copyable examples and accessible
  controls without adding dependencies or making configuration/network requests.
- Verify topic navigation, copy, context-specific initial topics and both desktop
  viewport sizes. Keep parent dialog state when nested help closes.

## Task 2: Empty preview classification

- Modify only `packages/cidr_data/lib/src/import.dart` and owning import tests.
- Add `ImportPreview.emptyRecordsMessage` constant for the existing empty-record
  diagnostic and `bool get isEmptyResult`: records empty and errors contain only
  that diagnostic (or no errors). Other malformed/validation errors exclude it.
- Retain raw errors, `canApply`, store validation and CLI exit behavior. Empty
  previews still cannot be applied. No schema or import merge changes.
- Test valid empty OCI/CSV/backup, invalid JSON/shape/domain/CIDR and nonempty cases.

## Task 3: Contextual UI and duplicate diagnostics

- Integrate Help into workspace header, Import, OCI discovery, and Planner.
- Clarify manual network and planning-pool/requested-size field guidance.
- In `ImportDialog`, do not invoke merged preview validation if initial preview
  cannot apply. Deduplicate displayed diagnostics. Track live-discovery origin
  explicitly; show neutral completion only when `isEmptyResult` is true for it.
- Empty discovery explains no manual prefix is needed; check the resource region
  and direct compartment, including child compartments. Keep Apply disabled.
  Provide a clearly named action to choose the discovery scope again. Preserve
  coverage/observation details behind an expandable disclosure.
- Test empty discovery, no duplicate errors/merge callback for invalid preview,
  malformed data still error/no apply, contextual Help and preserved selection,
  and a subsequent nonempty discovery still uses existing atomic Apply.

## Task 4: Verification and release

- Run owning package tests, app analyzer/widget suite, maintained-source format
  checks, and fresh scoped/integrated source review. Confirm previous imports,
  strict reservations and planner tests remain green.
- Document help examples and empty-result behavior in README/CONTRACT/PROJECT;
  bump app/CLI version to 0.2.1 (app build 3).
- Build app clean on this Mac; build CLI, run fictional preview smoke, and verify
  the DMG image, mounted contents, both architectures, signature integrity and
  checksum. Preserve existing releases; signing remains ad hoc.
- Publish the new tag/assets, compare uploaded sizes/digests to local artifacts,
  and verify private visibility. Keep builds/databases/customer data out of Git.
