# CIDR Atlas

A local, macOS-first register for OCI VCN and subnet CIDRs. Track allocations and
reservations, import discovered networks, and review conflicts within explicit
routing domains. The Flutter app and `cidrctl` CLI use the same pure Dart network
rules and local SQLite inventory.

This is an initial source release. The macOS application and CLI have been built
locally on Apple Silicon; see `PROJECT.md` for verification results and remaining
native UI checks. Distribution signing, notarization, and installer creation are
separate release work.

## Open as a Codex project

Place this folder at `~/projects/cidr-atlas` on your Mac, then open that folder as
a local project in Codex. Keep `AGENTS.md`, `PROJECT.md`, and the Git repository
at the project root. They preserve the architecture, implementation rules, and
next steps for subsequent Codex sessions. Read `PROJECT.md` for a ready-to-use
continuation prompt and current verification notes.

## Start on your Mac

Requirements:

- macOS with Flutter stable 3.47 or newer (source checks used Flutter 3.47.7 / Dart 3.13.5).
- Xcode, with its first-launch setup and command line developer tools configured.
- Any additional macOS dependencies reported by `flutter doctor -v`.

Use the official [Flutter installation](https://docs.flutter.dev/install/manual)
and [macOS setup](https://docs.flutter.dev/platform-integration/macos/setup)
instructions, then confirm the toolchain:

```bash
flutter doctor -v
flutter devices
```

If Xcode is installed but the active developer directory points to Command Line
Tools, select Xcode for the current terminal session:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Apple documents this session override in `man xcode-select`. The current native
plugins use [Flutter's Swift Package Manager integration](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers);
CocoaPods is not required for this dependency set.

From this directory:

```bash
cd apps/cidr_atlas
flutter pub get
flutter run -d macos
```

Alternatively, open `scripts/run_macos.command` from Finder. It uses Flutter on
your PATH, `~/development/flutter/bin/flutter`, or `~/flutter/bin/flutter`.
`FLUTTER_BIN` can specify another Flutter executable. The launcher does not
install system software.

To produce a local release build:

```bash
./scripts/build_macos.sh
```

The build output is `apps/cidr_atlas/build/macos/Build/Products/Release/`.
Distribution signing, notarization, App Store submission, and installer creation
are separate release work.

## First use

The app starts with an empty inventory. Optional demo records and the files under
`examples/` are explicitly fictional. Use a separate routing domain for each
independent address space; networks connected through a DRG, VPN, FastConnect, or
another cloud should share the relevant planning scope.

1. Add a parent allocation, such as `10.64.0.0/16`, in your routing domain.
2. Reserve a VCN range under that allocation, selecting its parent explicitly.
3. Add subnets under the VCN, or import an OCI inventory bundle.
4. Check a proposed CIDR before reserving it, and review the Conflicts view.
5. Export a JSON backup after important changes.

The desktop workspace provides an inventory table, search and filters, prefix
details, editing, conflict review, history, an address checker, a free-space
planner, import preview, and JSON/CSV export. The first release does not connect
to an OCI tenancy or store OCI credentials. Collect your own JSON exports and
import the files.

## Use the CLI

```bash
cd packages/cidr_cli
dart pub get
dart run bin/cidrctl.dart --help
```

`scripts/cidrctl` runs the source CLI from any directory. Build a standalone
executable on your target operating system with `scripts/build_cli.sh`.

Run these examples from the project root (`~/projects/cidr-atlas`):

```bash
./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  import csv --file examples/fictional_inventory.csv

# Imports are previews until --apply is supplied.
./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  import csv --file examples/fictional_inventory.csv --apply

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite list

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  check 10.64.32.0/20 --routing-domain example-corporate \
  --kind vcn --parent example-corporate-pool

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  reserve 10.64.32.0/20 --name future-qa-vcn \
  --routing-domain example-corporate --parent example-corporate-pool

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  import oci --file examples/fictional_oci_bundle.json \
  --routing-domain example-oci --apply

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  list --routing-domain example-oci --format json

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite \
  export --format json --file /tmp/cidr-atlas-backup.json

./scripts/cidrctl --db /tmp/cidr-atlas-demo.sqlite history
```

Global `--db` can also appear after the command. Without it, macOS uses
`~/Library/Application Support/cidr_atlas/inventory.sqlite`, shared with the app.
Linux uses `$XDG_DATA_HOME/cidr_atlas/inventory.sqlite`, falling back to
`~/.local/share/cidr_atlas/inventory.sqlite`. Windows uses
`%APPDATA%/cidr_atlas/inventory.sqlite` for the CLI. Use explicit `--db` when
coordinating non-macOS paths.

| Exit code | Meaning |
| --- | --- |
| `0` | Command succeeded, or import preview completed |
| `1` | File, storage, structural validation, or import failure |
| `2` | Invalid command usage |
| `3` | Proposed CIDR conflicts; reserve did not write it |

`check` reports conflicts involving its candidate only. Use `--parent` to declare
intentional containment. `--id` can identify a record being checked as an edit;
`reserve` creates new records and refuses an existing ID. Imports preserve
discovered conflicts for review, so a successful import does not certify that
the entire inventory is conflict-free.

Filtered `export` includes required parent allocations and matching OCI VCN
context, even when those ancestors do not match the filter, so the file can be
imported into an empty inventory. Filtered `list` output is a report and can omit
parents; use `export` for a portable backup.

## Imports and backup

CSV uses these case-sensitive headers:

```text
id,cidr,name,routingDomain,kind,status,customer,tenancy,region,compartment,environment,owner,resourceId,vcnId,parentId,notes,source,verifiedAt
```

`cidr`, `name`, and `routingDomain` are required. Exported CSV includes all
fields. `kind` is `allocation`, `vcn`, or `subnet`; `status` is `planned`,
`reserved`, `active`, or `retired`. When defining a hierarchy manually, use
stable record IDs and matching `parentId` values. CIDRs must be canonical network
prefixes: `10.64.1.3/24` is rejected instead of silently changed to `10.64.1.0/24`.

JSON backups contain `{"format":"cidr-atlas","version":1,"records":[...]}`.
Use an app/CLI JSON export as the template. A backup can be imported through the
JSON import workflow. Export and import are the supported transfer mechanism;
do not sync a live SQLite database through iCloud Drive or a shared folder.

OCI bundle imports accept VCN and subnet arrays plus coverage metadata. See
`examples/fictional_oci_bundle.json`. OCI CLI-style kebab-case fields are accepted;
raw `{"data":[...]}` CLI output is also supported. VCNs can have multiple CIDRs.
Specify a routing domain when importing OCI JSON. Include tenancy, region, and
coverage metadata in a bundle when available.

Set `metadata.collectedAt` to the actual inventory collection time in ISO 8601
format. That source observation time becomes `verifiedAt`; importing a file
today does not establish that its networks were observed today. If collection
time is unknown, the preview warns and leaves verification time unknown,
preserving a previously known time when reconciling an existing record. Import
history separately records when the file was applied.

Imports merge records by ID and reconcile matching OCI resource/CIDR identities
without deleting or automatically retiring absent resources. OCI reconciliation preserves local planning fields such as owner,
notes, status, parent, environment, and customer. A file that omits a resource is
not evidence that its address space has become free. Review the coverage warning
and import preview before applying changes.

## Data and boundaries

- All inventory stays local; there is no telemetry, hosted service, device sync,
  multi-user allocation service, or live OCI authentication in this release.
- Parent containment is valid only with an explicit valid hierarchy or a matching
  OCI VCN/subnet resource relationship. Numeric containment alone is not enough.
- Retired records do not block new allocations. Reservations do.
- Different routing domains may intentionally reuse CIDRs. Choose domains based
  on connectivity, not tenancy names alone.
- The checker validates inventory relationships and prefix conflicts. It does
  not infer route tables, DRG topology, or complete real-world reachability.
- Keep independent backups of important inventory. Export JSON for portable
  backups, and protect exported files according to your network-data policy.

## Development

```bash
cd packages/cidr_core && dart pub get && dart test
cd ../cidr_data && dart pub get && dart test
cd ../cidr_cli && dart pub get && dart test
cd ../../apps/cidr_atlas && flutter pub get && flutter analyze && flutter test
```

The commands above are individual development steps; run them from the indicated
package directories. The shared engine and CLI are portable Dart. iOS, Windows,
and Linux graphical releases and packaging remain future milestones.

See `docs/architecture.md` for component boundaries and
`docs/CONTRACT.md` for the implementation API contract.
