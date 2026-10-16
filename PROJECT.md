# CIDR Atlas

## Agreed direction

Mac-first desktop application for managing OCI VCN/subnet CIDRs and planning nonconflicting address allocations. Future iOS, Windows, and Linux applications share the same Dart engine; macOS, Windows, and Linux also have a CLI. Local SQLite initially. Offline CSV/OCI JSON imports precede live synchronization. Future team/device coordination requires a central authority.

## First milestone

- Exact IPv4/IPv6 engine and routing-domain-aware conflicts.
- Explicit address hierarchy, multiple VCN CIDRs, allocation planning.
- Local inventory with owner, environment, status, and audit history.
- Desktop workspace with search, filters, record editing, checker, import preview, and export.
- CLI and documented macOS build commands.

## Current state

The first source milestone is implemented: Flutter desktop workspace, exact CIDR engine, SQLite inventory/import/export, CLI, fictional samples, and Mac launch/build scripts. This Git repository is ready to be copied to `~/projects/cidr-atlas` and opened as the primary folder of a local Codex project. The cloud workspace cannot place files on the Mac or register that local project directly.

## Validation and remaining Mac checks

Checked in the Linux cloud environment with Dart 3.13.5 and Flutter 3.47.7 libraries:

- Core: 31 tests passed; analyzer clean.
- Data/imports: 44 tests passed; analyzer clean.
- CLI: 10 integration tests passed; analyzer clean; native Linux compilation and smoke checks passed.
- Flutter source and widget-test source: static Dart analysis passed. Seven widget tests are included but have not been executed.
- macOS plist/XML, platform template placeholders, and shell syntax checked.

A cloud approval review blocked Flutter setup because its command attempted cloud metadata access. That command was not retried. The macOS runner was assembled from the SDK's application templates without running Flutter. No macOS binary, native file-dialog verification, GUI render verification, signing, notarization, or GUI runtime testing has occurred. On the Mac, run the documented Flutter tests and native build, inspect the UI at 1100px and 1440px widths, test file import/export, and verify the app and CLI use the same database path.

The local app is configured for ordinary direct distribution with App Sandbox disabled, allowing its SQLite store to share the CLI default path. App Store sandboxing and release hardening require separate design/verification. No OCI credentials or live connections are used.

## Open in Codex on macOS

Extract the project to a normal development folder, for example `~/projects/cidr-atlas`. Add that folder to a local project in the ChatGPT desktop app's Codex experience. The primary project folder should be this directory so Codex discovers `AGENTS.md` and the Git repository. Ask Codex to read this file and verify the macOS build.

Initial continuation prompt:

> Read AGENTS.md and PROJECT.md. Verify the Flutter toolchain and Xcode on this Mac, resolve dependencies, run the tests, then build and launch the macOS app. Fix any macOS-specific issues and update the validation notes. Continue the existing Flutter/Dart architecture.

This is a local source project. No remote GitHub repository or hosted service is created automatically.
