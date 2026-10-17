# CIDR Atlas — project instructions

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Authorship

Sergio Farfan is the sole author of project-owned code and documentation. Use professional file headers identifying CIDR Atlas, the file's purpose, and `Author: Sergio Farfan <sergio.farfan@gmail.com>`. Preserve shebangs, required language directives, licenses, and third-party attribution. Do not add assistant authorship, co-author credits, generation notices, or internal workflow activity to source files or product documentation. Generated files retain their required tool and vendor notices.

## Product and user intent

Build a local-first CIDR inventory and allocation tool for an enterprise OCI infrastructure architect. Deliver macOS; Windows and Linux graphical releases are later milestones. iOS is dropped for now: the shared engine stays portable Dart, but no iOS app, iOS platform directory, or iOS-specific behavior is built or planned until that decision is revisited. Desktop platforms also need a CLI. The agreed architecture is Flutter UI, a pure Dart domain engine, and SQLite; do not switch to a website, Python service, or Swift-only implementation without discussing the tradeoff.

Read `docs/CONTRACT.md`, `docs/architecture.md`, and `PROJECT.md` for contracts, scope, and current implementation status.

## Layout

- `apps/cidr_atlas`: Flutter application; macOS is the only supported GUI target.
- `packages/cidr_core`: CIDR arithmetic, domain model, conflict and allocation rules. Must not import Flutter.
- `packages/cidr_data`: SQLite storage, atomic imports, exports, and history. Must not import Flutter.
- `packages/cidr_cli`: command-line frontend using the same core/data packages.
- `examples`: fictional inventories, never actual customer data or credentials.
- `scripts`: development/build entry points, no silent toolchain installation.

## Correctness rules

1. Use exact IPv4/IPv6 arithmetic. Reject malformed CIDRs and nonzero host bits; do not silently reserve a different range.
2. Conflicts are scoped by explicit routing domain, not tenancy alone.
3. Numerical containment does not imply an approved parent/child relationship. Validate explicit hierarchy or OCI VCN/subnet identity.
4. Multiple CIDRs per VCN require separate prefix records with shared resource identity.
5. Keep planning fields when refreshing observed OCI resources. Never free or delete missing CIDRs because an import is incomplete.
6. Imports must preview validation errors and commit atomically. Real discovered conflicts remain visible for review.
7. Do not synchronize a live SQLite database via shared folders. Future cross-device/team sync requires a service.
8. New installations start empty; demo data is optional and labeled fictional.
9. Do not read `~/.oci`, collect live data, or connect to OCI unless the user requests that feature. Current imports are offline.

## Workflow and verification

Keep implementation and tests in their owning packages. Delegate independent tasks when helpful; coordinate shared API changes. Run `dart format`, `dart analyze`, and meaningful core/data tests; run `flutter analyze` and widget tests for the app. Test parent relationships, domain reuse, IPv6 boundaries, persistence, and atomic imports when changing those behaviors.

Build macOS only on a Mac with Xcode. Linux checks cannot establish that macOS packaging, file dialogs, sandbox entitlements, or native SQLite work. Describe those limitations precisely. Do not claim an installable, signed, or notarized app exists unless the corresponding build and verification actually ran.

Never commit databases, imports containing real customer metadata, credentials, API keys, build output, or machine-specific SDK paths. Commit source and dependency lockfiles. Keep changes reviewable and document a useful next action in `PROJECT.md`.
