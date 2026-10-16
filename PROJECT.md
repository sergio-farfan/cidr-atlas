# CIDR Atlas

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Agreed direction

Mac-first desktop application for managing OCI VCN/subnet CIDRs and planning nonconflicting address allocations. Future iOS, Windows, and Linux applications share the same Dart engine; macOS, Windows, and Linux also have a CLI. Inventory is stored in local SQLite. Offline CSV/JSON imports and explicit read-only OCI CLI discovery share preview and atomic apply. Future team/device coordination requires a central authority.

## First milestone

- Exact IPv4/IPv6 engine and routing-domain-aware conflicts.
- Explicit address hierarchy, multiple VCN CIDRs, allocation planning.
- Local inventory with owner, environment, status, and audit history.
- Desktop workspace with search, filters, record editing, checker, import preview, and export.
- CLI and documented macOS build commands.

## Current state

The first milestone and the approved OCI CLI integration are implemented in the existing Flutter UI, pure Dart domain engine, and SQLite architecture. Both the app and desktop CLI can collect VCNs and subnets using an existing OCI profile, explicit authentication, region, compartment, and routing domain. Offline CSV/JSON imports remain available. Collection is read-only in OCI; only an explicit Apply writes the local inventory.

The private source repository is [sergio-farfan/cidr-atlas](https://github.com/sergio-farfan/cidr-atlas). Repository ownership and private visibility have been verified. The published [v0.1.0 macOS preview release](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0) contains the verified universal DMG and SHA-256 checksum. GitHub reports both assets uploaded; the remote DMG size and SHA-256 digest match the verified local artifact. The tag identifies source commit `6af1203f1720e38c2e19d804b6516b29ddfde1b4`. All reachable commit authors and committers use Sergio Farfan with the requested Gmail address.

## OCI import behavior

- `packages/cidr_oci` is a pure Dart adapter shared by the app and CLI. It returns an in-memory OCI JSON bundle and performs no database writes.
- The app's Import dialog offers **Discover from OCI CLI** alongside CSV/JSON file selection. Opening discovery reads profile metadata; **Load scopes** and **Discover inventory** are explicit network actions. API-key/security-token choice, configuration/executable overrides, READY regions, accessible compartments plus tenancy root, and manual scope fallback are supported.
- `cidrctl discover oci` requires `--profile`, `--region`, `--compartment-id`, and `--routing-domain`. It previews by default and writes only with `--apply`; optional `--config-file`, `--oci-bin`, and `--auth api_key|security_token` override local selection.
- One selected compartment and region are collected per run, with all pages and no descendant resource traversal. Missing referenced VCNs are fetched once by ID as context, without collecting their other subnets. Denied/not-found context is a coverage warning; required-list failures, malformed responses, cancellation, and timeouts return no applicable partial discovery.
- Requests have a 60-second deadline; complete collection has a 180-second deadline, followed by bounded child cleanup. Expired credentials require repair or renewal outside the app. No automatic sign-in or tooling installation is performed.
- The existing OCI JSON source identity, merge preview, and atomic transaction preserve planning metadata, retain absent resources, and expose real conflicts. Normalization includes additional subnet IPv4 and VCN BYOIPv6 aliases. UTC start/completion times and exact coverage describe a scoped observation over time, not a tenancy-wide or transactionally consistent snapshot.

Oracle assumptions were checked against installed OCI CLI 3.94.1 and official [configuration](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm), [token authentication](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm), [VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html), [subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html), and [VCN get](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html) documentation. The approved design in `docs/superpowers/specs/2026-10-15-oci-cli-live-import-design.md` records the complete command and data contract.

## Local validation

Toolchain: macOS 26.7.1 on Apple Silicon, Xcode 27.0 (27A266a) selected through the session's `DEVELOPER_DIR`, Flutter 3.47.7 (`abaf9c5237`), and Dart 3.13.5. The SDK is installed outside the repository. Dependency lockfiles are committed, including the new local adapter dependencies.

- Core: 31 tests passed; analyzer clean.
- Data/imports: 47 tests passed; analyzer clean, including CIDR alias normalization and OCI refresh preservation.
- CLI: 29 tests passed; analyzer clean. Existing CSV/JSON workflows and new discovery preview/apply, cancellation, failed collection, metadata preservation, domain isolation, absent resources, and visible conflicts were covered.
- Flutter: 22 widget tests passed; analyzer clean. Thirteen OCI workflow tests join nine workspace tests, covering 1100×740 and 1440×900 layouts, explicit selection, lifecycle/cancellation, manual scope fallback, and existing preview/apply integrity.
- OCI adapter: 55 tests passed; analyzer and formatting clean. Tests cover profile handling, command scope/environment, context, failures, deadlines, and controlled subprocess lifecycle.
- All maintained Dart source and tests passed nonmutating format checks. Two pre-existing app files were canonically formatted.
- The integrated `scripts/build_macos.sh` build produced a 44.3 MB universal release app (`x86_64` and `arm64`). `scripts/build_cli.sh` produced a 6,652,016-byte native `arm64` executable.
- Flutter migrated the Xcode project and scheme to Swift Package Manager and generated its Swift plugin registrant. All current plugins use Swift Package Manager, so the unused Podfile was removed; generated metadata and backups are ignored.
- The final compiled discovery CLI passed controlled fictional-executable smoke checks: preview with no inventory/history writes, explicit apply, failed second resource list preserving existing state, and actual SIGINT terminating the child without creating a database.
- Scoped reviews and the final integrated review passed after resolving profile-parser compatibility, expired-session diagnostics, and commit-email metadata.

Earlier Linux checks established portable baseline package behavior and a native Linux CLI build. They do not establish the new collector's Windows/Linux process behavior or graphical release packaging.

## Native smoke checks and remaining limits

Before OCI integration, the release app launched with an empty inventory and rendered at both 1440px and 1100px widths. The wide layout uses the details pane; the narrow layout opens a details dialog. A native CSV file dialog loaded six fictional prefixes into a preview without writing them. Applying the preview made the same six records visible through the CLI's default database. A native JSON save produced an exact six-record export, and quitting and reopening the app preserved all six records.

The app and CLI share `~/Library/Application Support/cidr_atlas/inventory.sqlite`. After checking that the smoke database contained exactly the six fictional records, it was moved to a temporary backup outside the repository. The app was reopened and the CLI confirmed that the default inventory is empty again.

The integrated release app launched successfully with an empty inventory. Its native Import dialog exposes both file selection and OCI discovery. Native file selection previewed six fictional CSV records and four fictional OCI JSON records with coverage and observation-time warnings. Cancelling the previews and cancelling file selection left the inventory empty. The new OCI discovery modal has widget coverage; native live selection/collection remains unverified. Native CSV save and a new native OCI JSON apply cycle remain additional checks; the baseline CSV apply/JSON export/persistence checks above remain the evidence for those existing shared paths. The local app has App Sandbox disabled to share the CLI database path. Signing is ad hoc; no Developer ID signing or notarization has been performed. App Store sandboxing and distribution hardening remain separate work.

Automated and controlled native discovery checks used fictional profiles, executables, and inventories. No actual OCI configuration or credential files were read, and no live OCI access occurred. Live profile validity, IAM permissions, and tenancy resource responses remain unverified. iOS, Windows, and Linux GUI releases remain future milestones.

## Release packaging

`scripts/build_dmg.sh` builds the macOS release app and creates `build/releases/CIDR-Atlas-0.1.0-macos-universal.dmg` with its `.sha256` file. It verifies universal architectures and code-signature integrity before packaging, verifies and mounts the image, checks the app, Applications shortcut, installation instructions, and third-party notices, then detaches it and validates the checksum. `--skip-build` packages an existing release build. Generated artifacts remain outside Git and are uploaded to GitHub Releases separately.

The initial DMG passed these checks on this Mac, including successful read-only mounting, both architecture checks and deep/strict signature verification on the mounted app, complete expected contents, successful detach, and SHA-256 verification. The image is 20,812,287 bytes. SHA-256: `d3b9f6b7d93e83cd3e43676cbd034c0166b26b589995056fc1021a0db3ca00c0`.

The initial release retains the ad hoc signature and has no Developer ID signature or notarization ticket. A mountable DMG and a verified local signature do not establish Gatekeeper acceptance on another Mac. Apple documents disk-image contents and formats in the [Disk Utility guide](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac); installed Apple command help is the source for packaging flags.

## Requested next action

The proposed next feature is a visual Address Space workspace, shared CIDR
inspector, and explainable right-sized CIDR recommendations. The design in
`docs/superpowers/specs/2026-10-15-visual-network-planning-design.md` incorporates
the requested calculator details, open-slot highlighting, community research,
and Oracle planning guidance. Its first milestone uses existing inventory;
observed topology connections are a subsequent milestone. The proposal has
passed a builder check and remains subject to scope review before implementation.

The next operational check is an explicitly selected existing OCI profile, region, compartment, and routing domain against live OCI, keeping any observed inventory outside the repository. Complete remaining native file-dialog checks and plan Developer ID signing/notarization before wider macOS distribution.

Keep credentials, customer inventories, generated builds, and machine-specific SDK paths out of Git.
