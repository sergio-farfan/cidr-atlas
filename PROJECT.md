# CIDR Atlas

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Agreed direction

Mac-first desktop application for managing OCI VCN/subnet CIDRs and planning nonconflicting address allocations. Future iOS, Windows, and Linux applications share the same Dart engine; macOS, Windows, and Linux also have a CLI. Local SQLite initially. Offline CSV/OCI JSON imports precede live synchronization. Future team/device coordination requires a central authority.

## First milestone

- Exact IPv4/IPv6 engine and routing-domain-aware conflicts.
- Explicit address hierarchy, multiple VCN CIDRs, allocation planning.
- Local inventory with owner, environment, status, and audit history.
- Desktop workspace with search, filters, record editing, checker, import preview, and export.
- CLI and documented macOS build commands.

## Current state

Verified locally on macOS on 2026-10-15. The first milestone is implemented: Flutter desktop workspace, exact CIDR engine, SQLite inventory/import/export, CLI, fictional samples, and Mac launch/build scripts. The macOS GUI and standalone CLI build and run on this Mac. Continue the existing Flutter UI, pure Dart domain engine, and SQLite architecture.

## Local validation

Toolchain: macOS 26.7.1 on Apple Silicon, Xcode 27.0 (27A266a) selected through the session's `DEVELOPER_DIR`, Flutter 3.47.7 (`abaf9c5237`), and Dart 3.13.5. The SDK is installed outside the repository; dependency lockfiles were restored unchanged.

- Core: 31 tests passed; analyzer clean.
- Data/imports: 44 tests passed; analyzer clean.
- CLI: 10 integration tests passed; analyzer clean. CSV/JSON round trips and OCI bundle import were tested.
- Flutter: 9 widget tests passed, covering 1100×740 and 1440×900 layouts; analyzer clean. Fixed layout overflows found by the original widget tests. Both changed Dart files are canonically formatted; `app.dart` also has substantial formatter reflow.
- Nonmutating format checks passed for all three pure Dart packages.
- `scripts/build_macos.sh` produced a 43.9 MB universal release app (`x86_64` and `arm64`). `scripts/build_cli.sh` produced a 6.1 MB native `arm64` executable.
- Flutter migrated the Xcode project and scheme to Swift Package Manager and generated its Swift plugin registrant. All current plugins use Swift Package Manager, so the unused Podfile was removed; generated metadata and backups are ignored.
- Local native and GUI reviews found no actionable issues.

Earlier Linux checks established portable package behavior and a native Linux CLI build. The local results above now establish macOS build and runtime behavior.

## Native smoke checks and remaining limits

The release app launched with an empty inventory and rendered at both 1440px and 1100px widths. The wide layout uses the details pane; the narrow layout opens a details dialog. A native CSV file dialog loaded six fictional prefixes into a preview without writing them. Applying the preview made the same six records visible through the CLI's default database. A native JSON save produced an exact six-record export, and quitting and reopening the app preserved all six records.

The app and CLI share `~/Library/Application Support/cidr_atlas/inventory.sqlite`. After checking that the smoke database contained exactly the six fictional records, it was moved to a temporary backup outside the repository. The app was reopened and the CLI confirmed that the default inventory is empty again.

Native CSV save, the complete OCI JSON GUI workflow, and file-dialog cancellation paths still need explicit checks. CLI coverage does not establish those native GUI paths. The local app has App Sandbox disabled to share the CLI database path. Signing is ad hoc for local execution only; no Developer ID signing, notarization, or installer has been produced. App Store sandboxing and distribution hardening remain separate work.

No OCI credentials were read and no live OCI access occurred during this validation. Current imports remain offline. iOS, Windows, and Linux GUI releases remain future milestones.

## Requested next action

Implement the approved read-only OCI CLI integration using an existing local profile, with region and compartment selection. The approved design is in `docs/superpowers/specs/2026-10-15-oci-cli-live-import-design.md`; it is not yet implemented in this checkout. Collection commands and fields were checked against official Oracle documentation and installed OCI CLI 3.94.1. Preserve import preview, atomic apply, planning fields, routing-domain scope, and incomplete-discovery warnings. Complete the remaining native file-dialog checks as part of desktop verification.

The private source repository is [sergio-farfan/cidr-atlas](https://github.com/sergio-farfan/cidr-atlas). Repository access and visibility have been verified. Keep credentials, customer inventories, generated builds, and machine-specific SDK paths out of Git.
