# CLAUDE.md

CIDR Atlas — repository guidance for coding agents working in this codebase.

Author: Sergio Farfan <sergio.farfan@gmail.com>

@AGENTS.md

`AGENTS.md` (imported above) holds the binding project rules: authorship headers, correctness rules, and verification expectations. `docs/CONTRACT.md` is the public API contract for every package, `docs/architecture.md` explains the design rationale, and `PROJECT.md` records the current status, verification counts, and next action.

## Commands

There is no Dart pub workspace. Each package has its own `pubspec.yaml` and `pubspec.lock` and depends on its siblings by `path:`, so run every command from inside the package directory. `dart` and `flutter` may not be on the PATH of a non-interactive shell; the SDK can live in a per-version toolchain folder outside PATH. Call the binaries by absolute path, or set `DART_BIN` / `FLUTTER_BIN`, which `scripts/cidrctl`, `build_cli.sh`, `build_macos.sh` and `run_macos.command` honor. Run `pub get` before trusting `analyze`.

Pure Dart packages (`packages/cidr_core`, `cidr_data`, `cidr_oci`, `cidr_cli`):

```bash
cd packages/cidr_data
dart pub get
dart format .
dart analyze
dart test                                   # whole package
dart test test/store_test.dart              # one file
dart test test/store_test.dart --name 'reserve'   # tests whose name matches
```

Flutter app (`apps/cidr_atlas`, macOS only):

```bash
cd apps/cidr_atlas
flutter pub get
flutter analyze
flutter test                                # widget tests
flutter test test/visual_planner_test.dart --plain-name 'recommend'
flutter run -d macos                        # or scripts/run_macos.command
```

Scripts (from the repo root):

- `scripts/cidrctl <args>`: runs the CLI from source from any directory. Without `--db` it uses the real shared inventory at `~/Library/Application Support/cidr_atlas/inventory.sqlite`. For experiments, always pass `--db ~/tmp/<name>.sqlite` (the README and user-guide examples do the same); never use `/tmp` on this machine.
- `scripts/build_cli.sh` compiles `build/cidrctl` for the current OS.
- `scripts/build_macos.sh` builds the release app. `scripts/build_dmg.sh [--skip-build]` packages and verifies the universal DMG under `build/releases/`. The DMG is ad hoc signed, with no notarization.

Lint configuration: every package has its own `analysis_options.yaml`. The four pure-Dart packages include `package:lints/recommended.yaml`, the app includes `package:flutter_lints/flutter.yaml`, and all add the same six rules as the root file (including `avoid_print`). `flutter pub get` re-adds the app's `build/**` and `macos/**` excludes.

## Architecture

Dependency direction: `cidr_core` ← `cidr_data` ← (`cidr_cli`, `apps/cidr_atlas`), and `cidr_oci` ← (`cidr_cli`, `apps/cidr_atlas`). `cidr_oci` depends on neither `cidr_core` nor `cidr_data`. Only the app imports Flutter.

- **cidr_core**: exact IPv4/IPv6 arithmetic (`Cidr`, `BigInt`), immutable `PrefixRecord`, `InventoryRules` (structural `validate` vs. reviewable `conflicts`, scoped by routing domain, with containment legitimate only through an explicit `parentId` chain or an OCI VCN/subnet identity match), and `AddressPlanner.plan`. The app's visual planner and the CLI's `recommend` command both use `AddressPlanner.plan`. UI geometry never decides availability.
- **cidr_data**: `InventoryStore` is a synchronous SQLite store (`sqlite3` package), with `InventoryStore.memory()` for tests. It has three write paths with different conflict semantics, and they must stay distinct:
  - `reserve` (planner and CLI allocation): new IDs only, and conflicts are rejected inside the write transaction.
  - `save(..., rejectConflicts:)` (manual edits).
  - `applyImport` (imports): conflicts are preserved for review. The batch is validated as a whole and committed atomically. Records are merged by ID, and OCI refreshes keep local planning fields. Absent records are never deleted or retired.
  - `delete`/`deleteAll` run in one transaction and refuse a parent that still has children.

  `InventoryImport.csv/json` produce an `ImportPreview`, and `mergedImportRecords` gives the same dry-run merge that `applyImport` commits. The merge protections rely on the source identities `ImportPreview.source == 'OCI JSON'` and record `source == 'oci'`, so do not relabel them. `defaultDatabasePath` (`lib/src/default_path.dart`) is the one default-location rule for the CLI and the app.
- **cidr_oci**: read-only collection through the user's installed `oci` CLI. It runs an executable plus an argument array with no shell, explicit profile/config/auth/region, an empty rc file, and a scrubbed environment. It reads only allowlisted profile metadata and never opens key or token files. It returns an in-memory bundle (`OciDiscovery.bundleJson`) and cannot write inventory. Both clients pass that bundle through `InventoryImport.json` and then `applyImport`. A required failure, timeout, or cancellation throws, and no partial bundle is returned. `OciCliClient` takes injected runner/environment/clock/command and collection timeouts/executable candidates for deterministic tests. Each command is bounded to 120 s; whole collection to 180 s (one pair) or 1800 s (`OciCollectionLimits`). `process_runner_test.dart` deliberately spawns real Dart child processes.
- **cidr_cli** (`cidrctl`): `runCidrctl` is synchronous for the existing commands. `runCidrctlAsync` adds `discover oci` and delegates everything else. Imports and discovery preview by default and write only with `--apply`. The exit codes are part of the contract: 0 ok/preview, 1 failure, 2 usage, 3 allocation conflict. Recommendation logic lives in `lib/src/recommendation.dart`, export-destination safety in `lib/src/export_file.dart`, and routing-domain warnings in `lib/src/routing_domains.dart`.
- **apps/cidr_atlas**: `main.dart` opens `defaultDatabasePath` from `cidr_data`, the same SQLite path as the CLI, and passes `OciDiscoveryDialog.defaultClientFactory` to `AtlasApp`. `AtlasController` (a `ChangeNotifier`) wraps the synchronous store. `app.dart` is the workspace shell (Inventory / Conflicts / Planner / History). `dialogs.dart` holds the record editor and the import preview. `oci_dialog.dart` holds `OciDiscoveryDialog`, which loads scopes and discovers only on explicit button presses. `visual_planner.dart` and `cidr_inspector.dart` render the core planner. `help.dart` provides the offline help topics. The app is not sandboxed, so it can launch the OCI CLI and share storage with the CLI.

Tests use only fictional data: `FakeOciInventoryClient` in the CLI tests and in `apps/cidr_atlas/test/fake_oci_client.dart` (shared by the app tests; the app injects it through `AtlasApp(ociClient:)` or an `OciClientFactory`), fake runners in `cidr_oci`, and `examples/` fixtures. Tests never touch a live tenancy or the default inventory database.

## Change discipline

- A change to a public API must stay consistent across core, data, CLI, and app, and must be reflected in `docs/CONTRACT.md`. Update `PROJECT.md` (status, test counts, next action) when behavior or verification changes.
- OCI CLI behavior claims, such as empty-list output, READY filtering, and compartment enumeration, are pinned to OCI CLI 3.94.1 and cited Oracle docs. Re-verify against the installed CLI's `--help` and the official docs before changing them.
- `build/`, `*.sqlite`, and `*.db` are gitignored. Never commit generated artifacts or inventories.
