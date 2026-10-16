# Contributing to CIDR Atlas

Author: Sergio Farfan <sergio.farfan@gmail.com>

CIDR Atlas is a local-first CIDR inventory and allocation tool for OCI networks:
a Flutter macOS app and the `cidrctl` CLI on a shared pure Dart engine and SQLite
store. Read these before changing code:

- [AGENTS.md](AGENTS.md): the binding project rules (authorship headers,
  correctness rules, verification expectations). They apply to every change.
- [CLAUDE.md](CLAUDE.md): commands, package layout and architecture.
- [docs/CONTRACT.md](docs/CONTRACT.md): the public API contract for each package;
  [docs/architecture.md](docs/architecture.md): design rationale;
  [PROJECT.md](PROJECT.md): current status, test counts and next actions.

## Build and test

There is no pub workspace. Each package resolves its own dependencies, so run
commands from inside the package directory. The Dart and Flutter SDKs may live
outside `PATH` (for example in a per-version toolchain folder); call them by
absolute path, or set `DART_BIN` / `FLUTTER_BIN`, which the scripts in `scripts/`
honor. CI uses Dart 3.13.5 and Flutter 3.47.7.

Pure Dart packages (`packages/cidr_core`, `cidr_data`, `cidr_oci`, `cidr_cli`):

```sh
cd packages/cidr_data
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

Flutter app (`apps/cidr_atlas`, macOS only):

```sh
cd apps/cidr_atlas
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Scripts, from the repository root: `scripts/cidrctl <args>` runs the CLI from
source, `scripts/run_macos.command` runs the app, and `scripts/build_cli.sh`,
`build_macos.sh` and `build_dmg.sh` produce release artifacts. Check script
changes with `bash -n`. For CLI experiments always pass
`--db ~/tmp/<name>.sqlite`; without `--db` the CLI opens the real shared
inventory.

The CI workflow runs the package checks on Linux for every push and pull request,
and the app checks on macOS for pushes to `main` and manual runs.

## Data and fixtures

Use fictional data only: fictional CIDR plans, names, regions and placeholder
OCIDs, as in `examples/`. Never commit or paste real tenancy data, OCIDs, OCI CLI
configuration, credentials, customer metadata, databases or build output. Tests
use fake OCI runners and in-memory or temporary stores; they never contact a live
tenancy or open the default inventory.

## Changes and pull requests

- Keep each change focused, with implementation and tests in the owning package.
  A public API change must stay consistent across core, data, CLI and app and be
  reflected in `docs/CONTRACT.md`.
- Add regression tests for bugs in CIDR arithmetic, conflicts, hierarchy,
  persistence, imports or OCI collection, including IPv6 boundaries where
  relevant.
- Update `PROJECT.md` when behavior or verification changes, and add user-visible
  changes under `## [Unreleased]` in `CHANGELOG.md`.
- Write commit subjects in sentence-case imperative without type prefixes, for
  example `Refuse dot-dot export paths to SQLite companions`.
- In the pull request, describe the changed behavior and the validation actually
  performed, including checks that were not performed (for example native macOS
  checks or live OCI discovery).

Releases are a separate maintainer action, documented in
[docs/releasing.md](docs/releasing.md). Report security problems privately as
described in [SECURITY.md](SECURITY.md).
