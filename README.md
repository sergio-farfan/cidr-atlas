<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.47">
  <img src="https://img.shields.io/badge/dart-3.13-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.13">
  <img src="https://img.shields.io/badge/storage-SQLite-003B57?style=flat-square&logo=sqlite&logoColor=white" alt="SQLite">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
</p>

# CIDR Atlas

Author: Sergio Farfan <sergio.farfan@gmail.com>

**Local-first CIDR inventory and allocation planning for OCI networks, with a macOS app and a desktop CLI.**

An enterprise OCI estate spreads VCNs and subnets across regions, compartments and
connected networks, and the question "is this range free?" usually means checking a
spreadsheet, the console and somebody's memory. CIDR Atlas keeps one local register of
allocations, reservations and discovered networks, checks conflicts inside explicit
routing domains, and recommends free space with exact IPv4/IPv6 arithmetic. The
Flutter app and the `cidrctl` CLI share the same pure Dart rules and the same local
SQLite inventory.

> **0.4.0 is prepared and not yet published.** The latest published preview is
> [0.3.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.3.0). See the
> [CHANGELOG](CHANGELOG.md) for what 0.4.0 adds and [PROJECT.md](PROJECT.md) for
> completed and outstanding verification.

## Download

Releases are on the private repository's
[releases page](https://github.com/sergio-farfan/cidr-atlas/releases); repository
access is required to download the assets. Each release provides a universal disk
image for Apple silicon and Intel and its SHA-256 checksum. From 0.4.0 the assets are
named `CIDR-Atlas-X.Y.Z.dmg` and `CIDR-Atlas-X.Y.Z.dmg.sha256`, plus an identical
stable-name `CIDR-Atlas.dmg`; 0.1.0 to 0.3.0 use `CIDR-Atlas-X.Y.Z-macos-universal.dmg`.

Open the disk image and drag **CIDR Atlas** to **Applications**. Quit a running copy
before replacing it. Upgrades keep the local inventory; new installations start empty.

<!-- UNSIGNED-NOTE: remove this block once notarized builds ship. -->
> CIDR Atlas releases are **ad-hoc signed and not notarized**. After verifying the
> download and its checksum and attempting to open it, macOS may require **System
> Settings → Privacy & Security → Open Anyway**. See
> [Apple's first-launch instructions](https://support.apple.com/en-lamr/102445).
> Developer ID signing and notarization are optional future improvements.

Prefer to build it yourself? See [Build from source](#build-from-source).

## Before you start

There are three ways to fill the inventory. Only live discovery needs anything
installed.

| Path | What you need |
|------|---------------|
| Add records by hand | Nothing. Start with an allocation such as `10.64.0.0/16`. |
| Import a file | A CSV file, a CIDR Atlas JSON backup, or an OCI JSON file ([formats](#import-file-formats)). No OCI access. |
| Discover from OCI | The OCI CLI, a working profile, and read-only IAM permissions ([setup](#oci-cli-setup)). |

### OCI CLI setup

CIDR Atlas runs your existing OCI CLI. It never stores credentials and never
reads key or token files; it reads only the profile name, tenancy, region and
whether the profile uses a session token.

1. **Install the OCI CLI** with Homebrew, Oracle's documented macOS method
   ([installation guide](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)):

   ```bash
   brew update && brew install oci-cli
   oci --version   # CIDR Atlas is validated against 3.94.1
   ```

   The app also finds `oci` in `~/bin`, `/opt/homebrew/bin` or `/usr/local/bin`,
   or you can choose the executable in the dialog (`--oci-bin` in the CLI).

2. **Create a profile** in `~/.oci/config`, either with an API key or a
   browser session ([token-based authentication](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm)):

   ```bash
   # API key: generates a key pair; upload the public key in the Console.
   oci setup config

   # Or a session token through the browser, then refresh it while it is valid.
   oci session authenticate --region us-ashburn-1
   oci session refresh --profile EXAMPLE --auth security_token
   ```

   Session tokens last one hour by default and can be refreshed up to 24 hours.
   Choose **Security token** in the dialog, or `--auth security_token` in the
   CLI, for a session profile.

3. **Grant read-only access.** Every request CIDR Atlas makes needs only the
   `inspect` verb ([core policy reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/corepolicyreference.htm),
   [IAM policy reference](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/iampolicyreference.htm)):

   ```text
   Allow group NetworkViewers to inspect tenancies in tenancy
   Allow group NetworkViewers to inspect compartments in tenancy
   Allow group NetworkViewers to inspect virtual-network-family in tenancy
   ```

   | Statement | Used for | API operations |
   |-----------|----------|----------------|
   | `inspect tenancies` | **Load scopes** and all READY regions | `ListRegionSubscriptions` |
   | `inspect compartments` | **Load scopes** and all accessible compartments | `ListCompartments` |
   | `inspect virtual-network-family` | VCN and subnet collection | `ListVcns`, `GetVcn`, `ListSubnets` |

   Scope the network statement to specific compartments if you prefer; discovery
   then needs those compartments selected, and a compartment you can see but not
   list networks in stops an all-compartments run. With manual scope entry
   (typed regions and a compartment OCID) the first two statements are not
   needed. `read` grants the same operations for these resources.

4. **Discover**: **Import → Discover from OCI CLI**, choose the profile, **Load
   scopes**, pick regions and compartments, enter a routing domain, and review the
   preview before **Apply**. See [Live OCI inventory](#live-oci-inventory).

### Import file formats

Every import is previewed first and applied in one transaction; nothing is
deleted because a file leaves it out. The `examples/` folder has fictional
templates for each format.

**CSV** — the first line is a header; columns can be in any order.
`cidr`, `name` and `routingDomain` are required. `kind` is `allocation`, `vcn`
or `subnet` (default `vcn`); `status` is `planned`, `reserved` (default),
`active` or `retired`; `parentId` links a record to its parent's `id`. CIDRs must
be canonical network prefixes (`10.64.1.0/24`, not `10.64.1.3/24`).

```text
id,cidr,name,routingDomain,kind,parentId
example-pool,10.64.0.0/16,Corporate allocation,example-corporate,allocation,
example-prod-vcn,10.64.0.0/20,Production VCN,example-corporate,vcn,example-pool
example-prod-app,10.64.1.0/24,Application subnet,example-corporate,subnet,example-prod-vcn
```

All columns: `id,cidr,name,routingDomain,kind,status,customer,tenancy,region,compartment,environment,owner,resourceId,vcnId,parentId,notes,source,verifiedAt`
(template: [`examples/fictional_inventory.csv`](examples/fictional_inventory.csv)).

**CIDR Atlas JSON backup** — `{"format":"cidr-atlas","version":1,"records":[...]}`,
as written by **Export → JSON** or `cidrctl export --format json`. Records keep
their own routing domains.

**OCI JSON** — import with a routing domain. Two shapes are accepted:

- A bundle with `metadata` (tenancy, region, `collectedAt`), `vcns` and
  `subnets`, like [`examples/fictional_oci_bundle.json`](examples/fictional_oci_bundle.json).
  This is the preferred file format because it records tenancy, region and
  observation time.
- Raw OCI CLI list output (`{"data":[...]}`), saved with `--all` so every page is
  included. Import the VCN and subnet files separately; tenancy, region and
  observation time are then unknown and the preview says so.

  ```bash
  oci network vcn list --compartment-id ocid1.compartment.oc1..example --all > vcns.json
  oci network subnet list --compartment-id ocid1.compartment.oc1..example --all > subnets.json
  ```

Field-level rules (partial-column updates, timestamps, aliases and merge
behavior) are in [Imports and backup](#imports-and-backup).

## Why CIDR Atlas?

**Routing domains, not tenancies, decide conflicts.** Networks joined by a DRG, VPN,
FastConnect or another cloud share an address space; isolated ones may reuse ranges.
Every record carries an explicit routing domain, and overlap checks stay inside it.

**Numerical containment is not hierarchy.** A subnet belongs to a VCN because you said
so or because OCI says so (matching VCN/subnet identity), never just because its range
falls inside another one. Unrelated overlaps are reported as conflicts.

**Discovery never deletes your plan.** OCI refreshes update observed fields, keep your
owner, notes, status and parent, and never retire or free a network that a partial
scan did not return. Every import is previewed, validated and committed atomically.

**Local and offline by default.** One SQLite file on your Mac, no account, no service,
no telemetry. OCI is contacted only when you start discovery, through your existing OCI
CLI profile, with read-only requests.

## Features

- **Inventory** of allocations, VCNs and subnets with routing domain, status, owner,
  environment, notes and OCI identity; multiple CIDRs per VCN are separate records.
- **Conflict review** scoped by routing domain, with explicit-parent and OCI-identity
  rules, and reviewable discovered conflicts.
- **Visual address planner** with free/blocked map, exact slot totals, bounded
  recommendations and OCI IPv4 demand sizing (`/16`–`/30`, three reserved addresses).
- **CIDR inspector** for masks, ranges, exact counts and containing supernets, IPv4 and
  IPv6.
- **Live OCI discovery** across one, several or all READY regions and one or all
  accessible compartments, with a centered progress panel, cancellation, collection
  limits and a one-click retry across all accessible compartments.
- **Offline imports** of CSV, CIDR Atlas JSON backups and OCI JSON bundles through the
  same preview and atomic apply.
- **Safe exports and clearing**: JSON/CSV export with formula escaping, and Clear
  inventory (everything or one routing domain) behind an explicit confirmation.
- **History** of local changes and import provenance.
- **Appearance** setting (System, Light or Dark) in Settings (gear icon or ⌘,);
  System follows macOS, and the choice applies immediately and is remembered.
- **`cidrctl` CLI** for list, check, reserve, recommend, import, discover, export,
  history and clear, with stable exit codes for scripting.

## Releases & Roadmap

Full details per release are in the [CHANGELOG](CHANGELOG.md); disk images are on the
[releases page](https://github.com/sergio-farfan/cidr-atlas/releases).

| Version | Date | Highlights |
|---------|------|------------|
| 0.4.0 | Prepared, unpublished | Review remediation, safer imports and exports, region canonicalization, OCI retries and collection limits, centered discovery progress, Clear inventory |
| [0.3.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.3.0) | 2026-10-15 | Multi-region and all-compartment discovery, compact planner layout |
| [0.2.1](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.1) | 2026-10-15 | Offline help, guidance and fictional examples |
| [0.2.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.0) | 2026-10-15 | Visual address planner and CIDR inspector |
| [0.1.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0) | 2026-10-15 | Initial macOS preview: inventory, OCI discovery, imports, CLI |

### Planned

Unordered and undated:

- **IPAM planning features** from the [Infoblox comparison](docs/design/2026-10-16-ipam-feature-assessment.md):
  a `cidrctl conflicts` gate, `recommend --count/--exclude`, OCI rule checks and OKE
  CIDR checks first.
- **Observed connectivity**: routes, gateways, DRGs and peering as a separate model;
  CIDR containment does not establish connectivity.
- **Discovery resilience**: an opt-in mode that records denied compartments as
  unobserved instead of stopping the collection.
- **Other platforms**: iOS, then Windows and Linux graphical releases.
- **Optional signing upgrade**: Developer ID signing and notarization.

## Build from source

Clone the private [source repository](https://github.com/sergio-farfan/cidr-atlas)
to `~/projects/git/cidr-atlas` on your Mac and open the folder in your development
environment. `AGENTS.md` defines project conventions, `PROJECT.md` records
implementation status and verification, and `docs/` contains the architecture
and API contracts.

### Prerequisites

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

### Run and build

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

To produce a local release build and disk image:

```bash
./scripts/build_macos.sh
./scripts/build_dmg.sh --skip-build
```

The app is written to `apps/cidr_atlas/build/macos/Build/Products/Release/`. The DMG
script checks that the app contains both `arm64` and `x86_64`, verifies its signature,
creates a compressed image, verifies and mounts it read-only, checks its contents, and
writes a SHA-256 checksum and the stable-name copy under `build/releases/`. Without
`--skip-build` it builds the app first. The image contains the app, an Applications
shortcut, installation instructions and third-party notices. Apple documents disk
images in the
[Disk Utility guide](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac).
The standalone CLI is built separately with `scripts/build_cli.sh`. The release
procedure is in [docs/releasing.md](docs/releasing.md).

## First use

Open **Help and examples** in the workspace header for a local guide with
copyable examples. **Import help**, **Discovery help**, and **Planner help** open
the relevant topic while retaining the form or preview. The guide covers OCI
scope selection, empty results, offline files, CIDR sizes, routing domains,
capacity, planning, and CLI usage. See the [user guide](docs/user-guide.md).

OCI discovery supplies existing CIDRs automatically. The preview count reports
returned networks; it does not ask you to type a prefix. Enter a full CIDR when
adding a manual record or specifying a planning boundary. In **Requested prefix
length**, enter the new child size, such as `24`, or use address-demand mode to
let the app select the size.

The app starts with an empty inventory. Optional demo records and the files under
`examples/` are explicitly fictional. **Explore with fictional sample data** adds
sample records, labeled with source `demo`, only to an empty inventory; **Remove
sample data** in the inventory table header removes all of them in one change.
**Clear inventory…** (the delete icon beside it) deletes every local record, or
one routing domain, after you type `CLEAR`; it offers **Export backup first**,
keeps change history and does not touch OCI.
Use a separate routing domain for each
independent address space; networks connected through a DRG, VPN, FastConnect, or
another cloud should share the relevant planning scope.

1. Add a parent allocation, such as `10.64.0.0/16`, in your routing domain.
2. Reserve a VCN range under that allocation, selecting its parent explicitly.
3. Add subnets under the VCN, discover from OCI CLI, or import a CSV/JSON file.
4. Check a proposed CIDR before reserving it, and review the Conflicts view.
5. Export a JSON backup after important changes.

The sidebar has **Inventory**, **Conflicts**, **Planner** and **History**.
**Settings** (the gear icon in the workspace header, **CIDR Atlas > Settings…**
or ⌘,) sets the **Appearance**: **System** (the default) follows the macOS
light or dark appearance, while **Light** and **Dark** fix the theme regardless of macOS. The
choice applies immediately and is kept in the app's user defaults. The
workspace provides an inventory table, search and filters, prefix details,
editing, conflict review, history, an address checker, a free-space planner,
import preview, and JSON/CSV export. Offline imports do not require OCI tooling
or a network connection.

Editor save errors appear inside the open editor and keep your input. For
records imported from OCI, the observed fields (name, CIDR, routing domain,
kind, tenancy, region, compartment, resource and VCN OCIDs) are read-only;
refresh from OCI to update them. Status, parent, customer, owner, environment
and notes stay editable. A parent with children cannot be deleted; the message
lists the children to delete or re-parent first. History shows the latest 100
changes, with **Load more** when older entries exist. **Export all** re-reads
the database first, because `cidrctl` can change it while the app is open.

## Visual address planning

Open **Planner**, explicitly choose a routing domain, and select an allocation or
VCN pool. The hierarchy groups OCI VCN prefixes by resource identity and shows
their known subnets. The address map highlights free intervals, blocked space,
conflicts, and the selected recommendation; free gaps are drawn above blocked
space. Zoom magnifies the address axis around the selected candidate, **Zoom to
candidate** centres it, and keyboard-selectable alternatives support reviewing
large pools. Refreshing the inventory, including **Export all**, clears current
results; select **Find available space** again. Compact planning controls sit
beside the main address map, with selected-network
details adjacent on wide windows. The **Address hierarchy** shows membership and
ancestry. Actual routes, gateways, DRGs and peering require a future observed
connectivity view; CIDR containment alone does not establish connections.

Choose a prefix length, or size an OCI IPv4 subnet from current/peak demand,
an explicit growth percentage, and separate additional demand. For example,
100 addresses, 20% growth, and four additional addresses require 124 assignable
addresses: an OCI `/25` provides 125 after its three reserved addresses. No growth
percentage is silently selected. Oracle recommends considering future expansion,
connected networks, and service requirements in its
[network sizing guidance](https://docs.oracle.com/en/solutions/oci-best-practices-networking/identify-vcn-topology-and-specifications1.html).

The inspector shows mask bits, IPv4 mask, network route, exact total addresses,
address range, possible subnet counts, and an explicitly selected containing
supernet. OCI IPv4 subnet policy applies only to `/16` through `/30` and displays
the provider's assignable range separately. Generic `/31` and `/32` remain valid
mathematical prefixes. IPv6 totals and slot counts use exact integers; provider
assignable counts are omitted because Oracle's current
[IPv6 comparison](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ipv6.htm)
and [VCN overview](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm)
differ on IPv6 reservations.

Available-address totals and aligned slots are separate: a partially occupied
slot cannot hold a new subnet even when it contains unused addresses. The app
shows exact totals with at most 12 recommendations. Ranking prefers the smallest
fitting free CIDR and aligned edges to preserve larger contiguous space; this is
an allocation heuristic. Review **Reserve** before saving locally. The transaction
rechecks the current inventory and refuses stale conflicts or duplicate IDs.
The sizing/ranking rationale is saved in notes and retained by OCI refreshes.
Recommendations establish availability only within the supplied inventory and
routing domain; review coverage and unimported connected address spaces first.

## Live OCI inventory

Use an existing OCI CLI installation and profile. The adapter was checked against
installed OCI CLI 3.94.1; command documentation currently identifies 3.95.0. OCI
configuration profiles and DEFAULT inheritance follow
[Oracle's configuration format](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm).
Without an explicit configuration file, CIDR Atlas uses `OCI_CLI_CONFIG_FILE`
when it is set, otherwise `~/.oci/config`. A Finder-launched app usually does
not see variables exported in a shell, so the app and `cidrctl` can read
different files for the same profile name; `cidrctl discover` prints the
configuration file and profile it used. An explicit configuration file and
executable path can be selected in the dialog or CLI. Without an explicit
executable, the OCI CLI is found on PATH, then at `~/bin/oci` (Oracle's
installer default), `/opt/homebrew/bin/oci` or `/usr/local/bin/oci`.

In the app, open **Import → Discover from OCI CLI**:

1. Choose a profile and confirm its tenancy, default region, and authentication
   mode: API key or security token. Opening this dialog reads selection metadata;
   it does not make OCI requests.
2. Select **Load scopes** to retrieve subscribed regions and accessible
   compartments. Choose one or several READY regions, or **All READY subscribed regions**.
   Independently choose one direct compartment or **All accessible compartments
   and subcompartments**. Compartments are listed by their path from the tenancy
   root, such as `root / prod / network`, and the selected OCID is shown below
   the selector. Manual comma-separated regions and compartment OCID entry
   remain available for narrow scopes when enumeration is unavailable; **Load
   scopes** in manual mode keeps what you typed. With tenancy root as the direct
   compartment, a hint notes that root usually holds no networks.
3. Enter the routing domain for connectivity and overlap checking, then select
   **Discover inventory**. A progress panel centred over the dialog shows the
   step, completed region/compartment scopes once known, elapsed time and the
   collection limit; its **Cancel** stops the request and returns to the form.
   The dialog's **Cancel** closes discovery and discards its result.
4. Review the prefix count, validation errors, conflicts, coverage, and observation
   interval in the existing import preview. **Apply** commits the validated batch
   atomically to SQLite; closing the preview leaves inventory unchanged.

Discovery reads each selected region/compartment pair, fetching all VCN and
subnet pages. Single-compartment mode collects direct resources only. The
all-compartments option freshly enumerates accessible active descendants from
tenancy root and includes root once, collecting their networks across the chosen
regions in one preview. All-region mode freshly selects READY subscriptions and
reports non-READY exclusions. Each resource retains its actual region. Regions
are full identifiers such as `us-ashburn-1` (any case) or three-letter region
keys such as `IAD`, which are resolved through the tenancy's region
subscriptions; `IAD` and `us-ashburn-1` together are one region. Other forms are
rejected before any request. Earlier versions stored the region as typed. A
refresh matches existing records by OCID rather than by region spelling, so a
network that v0.3.0 stored under an uppercase name or a region key is updated
in place: it keeps its owner, notes, status and parent and takes the canonical
region.

Oracle documents [root subtree and ACCESSIBLE enumeration](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html),
[region subscriptions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html),
and direct [VCN](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html)
and [subnet](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html)
resource calls. Accessible compartment visibility does not establish permission
to list its networks or visibility of IAM-hidden resources. A failed required
scope stops collection without an applicable partial bundle. Correct permissions
or choose a narrower scope to retry.

A successful empty list may have no CLI output. CIDR Atlas accepts this only for
the known list commands and shows a scope warning when both resource lists are
empty. Review region, compartment mode and permissions; root can be empty in direct mode. Genuine
malformed responses identify the failed step and expected structure without
displaying raw response contents. This follows the installed CLI's
[empty-list rendering behavior](https://github.com/oracle/oci-cli/blob/v3.94.1/src/oci_cli/cli_util.py#L893-L947).

An empty live preview now shows **Discovery completed — no networks found** with
scope guidance. After a direct single-compartment discovery, **Retry with all
accessible compartments** reruns it at once with the same profile, regions,
settings and routing domain, including subcompartments; **Review discovery
scope** opens a fresh dialog. No manual CIDR is
needed, and Apply stays disabled because there is nothing to save. Malformed data
still shows its validation error once. Expand **Coverage and observation details**
for provenance; the summary retains the relevant coverage warnings.

For a subnet whose VCN is absent from the selected-compartment list, discovery
fetches that VCN once by ID as relationship context. It does not enumerate that
VCN's other subnets. An inaccessible or missing context VCN produces a visible
coverage warning; it is not evidence that the VCN was deleted. Oracle exposes
this individual lookup through [Get VCN](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html).
Required-list failures, malformed responses, cancellation, and timeouts prevent a
partial discovery from reaching Apply. Each OCI CLI request uses a 10-second
connection timeout, a 15-second read timeout and `--max-retries 3`, which in OCI
CLI 3.94.1 means three attempts in total. Each command is bounded to 120
seconds. Complete collection is bounded to 180 seconds for one selected pair, or
1800 seconds for broader modes, followed by bounded process cleanup. For a large
scope, set a longer limit in the dialog's **Collection time limit, minutes
(optional)** field (1 to 1440) or with `--collection-timeout SECONDS` (30 to
86400). A collection that reaches its limit returns nothing to apply. Progress
shows the current scope; Cancel/Ctrl-C stops collection without applying it.

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

Run these examples from the project root (`~/projects/git/cidr-atlas`). They keep
the example database and backup in `~/tmp` inside your home directory. Keep
live-discovery databases and exports in a protected directory, not a shared one
such as `/tmp`.

```bash
mkdir -p ~/tmp

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  import csv --file examples/fictional_inventory.csv

# Imports are previews until --apply is supplied.
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  import csv --file examples/fictional_inventory.csv --apply

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite list

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  check 10.64.32.0/20 --routing-domain example-corporate \
  --kind vcn --parent example-corporate-pool

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  reserve 10.64.32.0/20 --name future-qa-vcn \
  --routing-domain example-corporate --parent example-corporate-pool

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  import oci --file examples/fictional_oci_bundle.json \
  --routing-domain example-oci --apply

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  list --routing-domain example-oci --format json

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  export --format json --file ~/tmp/cidr-atlas-backup.json

./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite history
```

Live discovery uses the same preview/apply rules. Replace the fictional profile,
region, compartment OCID, and routing domain with your intended scope:

```bash
mkdir -p ~/tmp

# Preview only; no inventory or history records are written.
./scripts/cidrctl --db ~/tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1 \
  --compartment-id ocid1.compartment.oc1..example \
  --routing-domain example-connected

# Apply only after reviewing the same scope and authentication settings.
./scripts/cidrctl --db ~/tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1 \
  --compartment-id ocid1.compartment.oc1..example \
  --routing-domain example-connected --apply

# Multiple selected regions, all accessible compartments; preview only.
./scripts/cidrctl --db ~/tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1,us-ashburn-1 \
  --all-compartments --routing-domain example-connected

# All READY regions and accessible compartments/subcompartments; preview only.
./scripts/cidrctl --db ~/tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --all-regions --all-compartments \
  --routing-domain example-connected

# Optional explicit paths and authentication override.
./scripts/cidrctl --db ~/tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --region us-phoenix-1 \
  --compartment-id ocid1.compartment.oc1..example \
  --routing-domain example-connected \
  --config-file "$HOME/.oci/config" --oci-bin /opt/homebrew/bin/oci \
  --auth security_token

# A broad scope that needs more than the default 1800-second limit.
./scripts/cidrctl --db ~/tmp/cidr-atlas-live.sqlite discover oci \
  --profile EXAMPLE --all-regions --all-compartments \
  --routing-domain example-connected --collection-timeout 3600
```

`clear` deletes local records only; OCI is never contacted. Export a copy first:

```bash
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  export --file ~/tmp/cidr-atlas-backup.json

# Only one exact routing domain.
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite \
  clear --routing-domain example-oci --yes

# Every local record.
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite clear --yes
```

`--yes` is required; without it the command exits 2 and changes nothing. The
delete is one transaction with one `delete` history entry, and prints `Cleared N
records from the local inventory. OCI resources were not changed.` (or `from
routing domain DOMAIN`). Nothing to delete prints `No records to clear.` and
exits 0, after the usual warning when the routing domain is unknown. `clear`
never creates an inventory: a missing database file exits 1 with `Inventory not
found: PATH. Clear never creates an inventory; check --db.` A record in another
routing domain that names a cleared record as its parent blocks the clear (exit
1, nothing deleted).

`--auth` accepts `api_key` or `security_token`; without it, authentication follows
the selected profile's token metadata. Profile and routing domain are required.
Choose repeated/comma-separated `--region` or `--all-regions`, and
`--compartment-id` or `--all-compartments`; each pair is mutually exclusive. A new discovery command collects a new observation, so its preview may
differ from an earlier run. The database path is checked before any OCI request.
Progress goes to stderr: the configuration file and profile used, then the scope
count and limit, for example `Collecting 1 region/compartment scope with 2
sequential list requests within the 180-second default collection limit.`, then
each scope. Warnings and the preview go to stdout. Ctrl-C cancels collection
before apply. A successful nonempty preview can create the selected local
database file, with a stderr warning, but writes no inventory or history
records. A successful discovery that finds no networks prints `Discovery
completed: no networks were found in the selected scope. No records were
changed.` and exits 0, with or without `--apply`, without creating a database.

Global `--db` can also appear after the command. Without it, the CLI and the app
use the same default: macOS
`~/Library/Application Support/cidr_atlas/inventory.sqlite`, Linux
`$XDG_DATA_HOME/cidr_atlas/inventory.sqlite` when `XDG_DATA_HOME` is an absolute
path, otherwise `~/.local/share/cidr_atlas/inventory.sqlite`, and Windows
`%APPDATA%/cidr_atlas/inventory.sqlite`. A relative or empty `XDG_DATA_HOME` is
ignored, as the XDG specification requires. Any command that creates a new
empty database file warns on stderr, so a mistyped `--db` is visible.

The CLI uses the same recommendation engine. These examples use a manually
specified, fictional boundary; add `--parent ID` when selecting an existing pool:

```bash
mkdir -p ~/tmp

# Preview aligned /24 candidates and exact slot totals.
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite recommend \
  --pool 10.90.0.0/20 --routing-domain example-connected \
  --prefix 24 --format json

# Explicit demand sizing: 100 + 20% + 4 = 124 assignable addresses.
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite recommend \
  --pool 10.90.0.0/20 --routing-domain example-connected \
  --addresses 100 --growth-percent 20 --additional 4 \
  --basis current --policy oci_ipv4 --kind subnet

# Reserve the first ranked candidate only after reviewing the same inputs.
./scripts/cidrctl --db ~/tmp/cidr-atlas-demo.sqlite recommend \
  --pool 10.90.0.0/20 --routing-domain example-connected \
  --addresses 100 --growth-percent 20 --additional 4 \
  --basis current --policy oci_ipv4 --kind subnet \
  --apply --name example-subnet
```

`--prefix` and `--addresses` are mutually exclusive. Demand requires an explicit
`--growth-percent`, including zero when no further growth is intended; label an
already planned peak with `--basis peak`. `--additional` defaults to zero.
`--limit` defaults to 12. JSON encodes exact address/slot integers as decimal
strings. A preview writes no inventory or history records, though opening a new
database path can create the file. A no-fit preview returns 0 with a warning; in
scripts, use `--format json` and check for zero candidates. `--apply` with no
candidate returns 1, invalid usage 2, and a stale conflicting apply 3. Generic
prefix planning also supports IPv6.

| Exit code | Meaning |
| --- | --- |
| `0` | Command succeeded, or import preview completed |
| `1` | File, storage, discovery, structural validation, or import failure, including `clear` with a missing database |
| `2` | Invalid command usage, including a blank `--db`, a missing `HOME`/`APPDATA` without `--db`, an OCI bundle without `--routing-domain`, `--routing-domain` with a CSV or Atlas backup, `export --file` naming the open database, and `clear` without `--yes` |
| `3` | Proposed CIDR conflicts; reserve did not write it |

`check` reports conflicts involving its candidate only. Use `--parent` to declare
intentional containment. `--id` can identify a record being checked as an edit;
`reserve` creates new records and refuses an existing ID (exit 1). `check`,
`reserve`, `recommend`, `discover` and OCI JSON import warn on stderr when the
routing domain has no non-retired records, suggesting near matches such as a
different letter case; domains are still matched exactly. Imports preserve
discovered conflicts for review, so a successful import does not certify that
the entire inventory is conflict-free.

Filtered `export` includes required parent allocations and matching OCI VCN
context, even when those ancestors do not match the filter, so the file can be
imported into an empty inventory. Filtered `list` output is a report and can omit
parents; use `export` for a portable backup. `export --file` refuses the open
database and its `-wal`, `-shm` and `-journal` files, including through
symbolic links. An existing export file is replaced atomically and keeps its
permission mode.

## Imports and backup

CSV uses the following documented headers:

```text
id,cidr,name,routingDomain,kind,status,customer,tenancy,region,compartment,environment,owner,resourceId,vcnId,parentId,notes,source,verifiedAt
```

`cidr`, `name`, and `routingDomain` are required. Exported CSV includes all
fields. `kind` is `allocation`, `vcn`, or `subnet`; `status` is `planned`,
`reserved`, `active`, or `retired`. When defining a hierarchy manually, use
stable record IDs and matching `parentId` values. CIDRs must be canonical network
prefixes: `10.64.1.3/24` is rejected instead of silently changed to `10.64.1.0/24`,
and a prefix length with leading zeros such as `/08` is rejected.

A CSV row whose `id` matches an existing record updates only the columns in the
file's header; absent columns, including `status`, `kind`, `source` and
`verifiedAt`, keep their existing values. A column that is present but blank
clears that field (blank `status`, `kind` or `source` resets to `reserved`,
`vcn` or `csv`). Rows without an `id` receive a stable generated ID, so
re-importing the same file is idempotent. Two such rows describing the same
CIDR, kind, routing domain and resource ID are an error, and an id-less row that
matches an existing record with a different name or customer produces a
warning; add an `id` column to keep both.

`verifiedAt` in CSV files and JSON backups should include `Z` or a UTC offset,
such as `2026-10-15T18:30:00Z`, and must be a valid calendar date and time;
values are stored and exported in UTC. Zone-less timestamps, which v0.3.0 wrote
in its exports and backups, are read as local time, and the preview warns how
many values were read that way. Rolled-over or unparseable values are rejected
with a row-numbered error. Exported CSV prefixes `'` to any cell that a
spreadsheet would evaluate as a formula (starting with `=`, `+`, `-`, `@`, tab
or carriage return), and import removes that quote, so exports round-trip
unchanged. In a hand-written CSV, a literal leading `'` before one of those
characters is removed on import.

JSON backups contain `{"format":"cidr-atlas","version":1,"records":[...]}`.
Use an app/CLI JSON export as the template. A backup can be imported through the
JSON import workflow; a backup record replaces the whole existing record with
the same ID. Export and import are the supported transfer mechanism;
do not sync a live SQLite database through iCloud Drive or a shared folder.

OCI bundle imports accept VCN and subnet arrays plus coverage metadata. See
`examples/fictional_oci_bundle.json`. OCI CLI-style kebab-case fields are accepted;
raw `{"data":[...]}` CLI output is also supported; save it with the OCI CLI's
`--all` option. A single page that still carries `opc-next-page` produces a
warning, because unlisted ranges would appear free. VCNs can have multiple CIDRs.
Normalization includes subnet `ipv4-cidr-blocks`/`ipv4CidrBlocks` and VCN
`byoipv6-cidr-blocks`/`byoipv6CidrBlocks`, deduplicated with existing aliases
by canonical CIDR.
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
and import preview before applying changes. The OCI preview also warns when a
record you marked retired is still observed live (it stays retired, so its
space counts as free), and when the bundle is older than an existing
observation (applying rolls those records' observed fields and `verifiedAt`
back to the bundle's time).

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

## Contributing and verification

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and conventions, `AGENTS.md` for the
binding project rules, and [docs/releasing.md](docs/releasing.md) for the release
procedure. Each package is checked on its own:

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
`docs/CONTRACT.md` for the implementation API contract. Report security issues as
described in [SECURITY.md](SECURITY.md).

## Uninstall

Quit the app, then remove it and, only if you no longer need it, the local inventory.
The appearance preference is not part of the inventory; it lives in the app's user
defaults (domain `dev.cidratlas.desktop`):

```bash
rm -rf "/Applications/CIDR Atlas.app"
# Optional: removes the appearance preference.
defaults delete dev.cidratlas.desktop theme.appearance
# Optional: deletes every local record. Export a backup first.
rm -rf "$HOME/Library/Application Support/cidr_atlas"
```

## License

[MIT](LICENSE) — Sergio Farfan (sergio.farfan@gmail.com). Third-party notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
