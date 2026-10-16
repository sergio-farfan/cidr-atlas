# CIDR Atlas

Author: Sergio Farfan <sergio.farfan@gmail.com>

A local, macOS-first register for OCI VCN and subnet CIDRs. Track allocations and
reservations, import discovered networks, and review conflicts within explicit
routing domains. The Flutter app and `cidrctl` CLI use the same pure Dart network
rules and local SQLite inventory.

The macOS application and CLI have been built locally on Apple Silicon. Import
live OCI inventory through an existing CLI profile, or use offline CSV and JSON
files. Both paths provide a preview before an atomic local import. See
`PROJECT.md` for verification results and remaining native checks.

## Development workspace

Clone the private [source repository](https://github.com/sergio-farfan/cidr-atlas)
to `~/projects/cidr-atlas` on your Mac and open the folder in your development
environment. `AGENTS.md` defines project conventions, `PROJECT.md` records
implementation status and verification, and `docs/` contains the architecture
and API contracts.

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

## macOS releases

The private repository's [v0.1.0 release page](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0)
is the destination for the universal macOS DMG and its SHA-256 checksum. Repository
access is required to download private release assets.

Build the disk image on a Mac with the requirements above:

```bash
./scripts/build_dmg.sh
```

The script builds the app, checks that it contains both `arm64` and `x86_64`
architectures, creates a compressed DMG, verifies and mounts it, checks its
contents, then writes a SHA-256 checksum. Use `--skip-build` only when packaging
an existing release build. Output is written under `build/releases/`:

```text
CIDR-Atlas-0.1.0-macos-universal.dmg
CIDR-Atlas-0.1.0-macos-universal.dmg.sha256
```

The image contains the app, an Applications shortcut, installation instructions,
and third-party notices. Drag the app to Applications and eject the image. This
initial build uses an ad hoc signature; it has no Developer ID signature or Apple
notarization ticket, so macOS may require explicit approval to open it. Packaging
does not establish notarization. Apple documents disk images in the
[Disk Utility guide](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac);
the script's command options are checked against the installed `hdiutil` tools.
The standalone CLI is built separately with `scripts/build_cli.sh`.

## First use

The app starts with an empty inventory. Optional demo records and the files under
`examples/` are explicitly fictional. Use a separate routing domain for each
independent address space; networks connected through a DRG, VPN, FastConnect, or
another cloud should share the relevant planning scope.

1. Add a parent allocation, such as `10.64.0.0/16`, in your routing domain.
2. Reserve a VCN range under that allocation, selecting its parent explicitly.
3. Add subnets under the VCN, discover from OCI CLI, or import a CSV/JSON file.
4. Check a proposed CIDR before reserving it, and review the Conflicts view.
5. Export a JSON backup after important changes.

The desktop workspace provides an inventory table, search and filters, prefix
details, editing, conflict review, history, an address checker, a free-space
planner, import preview, and JSON/CSV export. Offline imports do not require OCI
tooling or a network connection.

## Live OCI inventory

Use an existing OCI CLI installation and profile. The adapter was checked against
installed OCI CLI 3.94.1; command documentation currently identifies 3.95.0. OCI
configuration profiles and DEFAULT inheritance follow
[Oracle's configuration format](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm).
The default macOS configuration is `~/.oci/config`; an explicit configuration
file and executable path can be selected in the dialog or CLI.

In the app, open **Import → Discover from OCI CLI**:

1. Choose a profile and confirm its tenancy, default region, and authentication
   mode: API key or security token. Opening this dialog reads selection metadata;
   it does not make OCI requests.
2. Select **Load scopes** to retrieve subscribed regions and accessible
   compartments. Choose a READY region and a compartment, including the tenancy
   root when appropriate. Manual region and compartment OCID entry is available
   when IAM prevents scope enumeration.
3. Enter the routing domain for connectivity and overlap checking, then select
   **Discover inventory**. Cancel stops collection and discards its result.
4. Review the prefix count, validation errors, conflicts, coverage, and observation
   interval in the existing import preview. **Apply** commits the validated batch
   atomically to SQLite; closing the preview leaves inventory unchanged.

Each run lists VCNs and subnets directly in one selected compartment and region,
fetching all pages. Selecting a parent compartment or the tenancy root does not
collect descendants. The subnet list is not restricted to VCNs in that compartment.
These choices use the documented [VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html)
and [subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html)
scope and pagination options.

For a subnet whose VCN is absent from the selected-compartment list, discovery
fetches that VCN once by ID as relationship context. It does not enumerate that
VCN's other subnets. An inaccessible or missing context VCN produces a visible
coverage warning; it is not evidence that the VCN was deleted. Oracle exposes
this individual lookup through [Get VCN](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html).
Required-list failures, malformed responses, cancellation, and timeouts prevent a
partial discovery from reaching Apply. Requests have a 60-second deadline and a
complete collection has a 180-second deadline, followed by bounded process
cleanup.

The app reads allowlisted profile metadata and leaves private-key and token-file
access to the OCI CLI process. It creates no credentials and opens no automatic
sign-in session. Renew or repair an expired session outside the app, then retry;
Oracle describes the supported session lifecycle in
[Token-based Authentication](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm).
Each request explicitly fixes profile, authentication, configuration, region, and
JSON output, and isolates CLI rc defaults and OCI environment overrides. OS proxy
and TLS trust settings, including `OCI_CLI_CERT_BUNDLE`, are preserved. See
[Oracle's option precedence](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clienvironmentvariables.htm)
and [CLI rc configuration](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm).

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

Live discovery uses the same preview/apply rules. Replace the fictional profile,
region, compartment OCID, and routing domain with your intended scope:

```bash
# Preview only; no inventory or history records are written.
./scripts/cidrctl --db /tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1 \
  --compartment-id ocid1.compartment.oc1..example \
  --routing-domain example-connected

# Apply only after reviewing the same scope and authentication settings.
./scripts/cidrctl --db /tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1 \
  --compartment-id ocid1.compartment.oc1..example \
  --routing-domain example-connected --apply

# Optional explicit paths and authentication override.
./scripts/cidrctl --db /tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1 \
  --compartment-id ocid1.compartment.oc1..example \
  --routing-domain example-connected \
  --config-file "$HOME/.oci/config" --oci-bin /opt/homebrew/bin/oci \
  --auth security_token
```

`--auth` accepts `api_key` or `security_token`; without it, authentication follows
the selected profile's token metadata. All four scope options are
required. A new discovery command collects a new observation, so its preview may
differ from an earlier run. Progress goes to stderr; warnings and the preview go
to stdout. Ctrl-C cancels collection before apply. A successful preview can create
the selected local database file but writes no inventory or history records.

Global `--db` can also appear after the command. Without it, macOS uses
`~/Library/Application Support/cidr_atlas/inventory.sqlite`, shared with the app.
Linux uses `$XDG_DATA_HOME/cidr_atlas/inventory.sqlite`, falling back to
`~/.local/share/cidr_atlas/inventory.sqlite`. Windows uses
`%APPDATA%/cidr_atlas/inventory.sqlite` for the CLI. Use explicit `--db` when
coordinating non-macOS paths.

| Exit code | Meaning |
| --- | --- |
| `0` | Command succeeded, or import preview completed |
| `1` | File, storage, discovery, structural validation, or import failure |
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
Normalization includes subnet `ipv4-cidr-blocks`/`ipv4CidrBlocks` and VCN
`byoipv6-cidr-blocks`/`byoipv6CidrBlocks`, deduplicated with existing aliases.
Each distinct prefix remains a separate record sharing the resource identity.
Specify a routing domain when importing OCI JSON. Include tenancy, region, and
coverage metadata in a bundle when available.

Set `metadata.collectedAt` to the actual inventory collection time in ISO 8601
format. That source observation time becomes `verifiedAt`; importing a file
today does not establish that its networks were observed today. If collection
time is unknown, the preview warns and leaves verification time unknown,
preserving a previously known time when reconciling an existing record. Import
history separately records when the file was applied.

Live bundles also record `metadata.collectionStartedAt`. Their coverage identifies
the selected scope, all-page resource lists, VCN context results, and collection
interval. This is a scoped observation over time, not a complete or transactionally
consistent tenancy snapshot.

Imports merge records by ID and reconcile matching OCI resource/CIDR identities
without deleting or automatically retiring absent resources. OCI reconciliation preserves local planning fields such as owner,
notes, status, parent, environment, and customer. A file that omits a resource is
not evidence that its address space has become free. Review the coverage warning
and import preview before applying changes.

## Data and boundaries

- Inventory stays in local SQLite. Live discovery makes only the explicitly
  requested OCI reads; there is no telemetry, hosted inventory service, device
  sync, multi-user allocation service, or scheduled background collection.
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
cd ../cidr_oci && dart pub get && dart test
cd ../cidr_cli && dart pub get && dart test
cd ../../apps/cidr_atlas && flutter pub get && flutter analyze && flutter test
```

The commands above are individual development steps; run them from the indicated
package directories. The shared engine and CLI are portable Dart. iOS, Windows,
and Linux graphical releases and packaging remain future milestones.

See `docs/architecture.md` for component boundaries and
`docs/CONTRACT.md` for the implementation API contract.
