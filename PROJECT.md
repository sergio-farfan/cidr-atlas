# CIDR Atlas — implementation status

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Product direction

Local-first CIDR inventory and allocation planning for cloud/network administrators.
The macOS Flutter app and desktop CLI share pure Dart network rules, OCI discovery,
and a local SQLite inventory. Offline CSV/JSON imports remain available. iOS,
Windows and Linux graphical releases and team synchronization are future work.
New installations start empty; optional demo inventories are fictional.

## Current implementation

The v0.3.0 implementation adds one/several selected regions or all READY subscribed
regions, independently paired with one direct compartment or all accessible active
compartments and subcompartments, including tenancy root. It collects all resource
pages for each region/compartment pair into one preview. Every resource retains its
actual region and compartment; refresh preserves planning metadata and absent
records. Accessible compartment visibility does not guarantee network-list access
or visibility of IAM-hidden resources. Required failures stop collection without
an applicable partial bundle. Offline imports, preview and atomic apply are retained.

The planner uses compact planning controls beside the main address map, with an
adjacent selected-network inspector when width permits. It shows address hierarchy,
OCI VCN membership, conflicts, blocked/free space, exact slot totals and bounded
recommendations. Address containment does not establish connectivity. A topology
view needs observed routes, gateways, DRGs, peering and security resources; those
remain a separate collection/storage milestone.

The shared CIDR inspector shows prefix/host bits, IPv4 mask, network and address
range, exact counts, theoretical child slots and a selected containing supernet.
OCI IPv4 subnet capacity supports /16 through /30 with three reserved addresses.
Demand sizing requires explicit growth and separate additional demand. IPv6 uses
exact integers without inventing an OCI assignable-host policy. Availability is
conditional on inventory coverage and the explicit routing domain.

Local reservations recheck identity, structure and current conflicts in the SQLite
write transaction. Imported conflicts remain reviewable. Refresh retains local
owner, notes, status, parent, environment and customer fields and never deletes or
retires omitted resources. Source observation time remains distinct from apply time.

Offline Help and examples and the [user guide](docs/user-guide.md) explain scope
selection, empty results, manual CIDRs, planning prefixes, capacity and routing
domains with fictional copyable examples. Empty live results keep Apply disabled;
validation errors remain visible without duplicates. Coverage is expandable.

## OCI collection contract

The shared adapter uses an existing local OCI CLI/profile; private-key and token
access stays within the CLI. Metadata selection is explicit, as are network
requests. There is no automatic sign-in, provisioning, background collection or
credential creation. Requests use explicit profile/config/auth/region/JSON,
isolated rc/environment defaults, all pages and bounded retries.

Collection is sequential with progress, cancellation and safe operation/scope
errors. Per-command deadline is 60 seconds; whole collection defaults to 180
seconds for one selected pair and 1800 seconds for broader modes. A required
failure returns no bundle. Denied/not-found referenced VCN context remains a
warning; context queries use the actual region. Coverage records modes, actual
regions/compartments, completed scopes/resource counts, observation interval and
context outcomes. It is not a complete or transactionally consistent tenancy audit.

Validated against installed OCI CLI 3.94.1 and Oracle's
[compartment list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html),
[region subscriptions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html),
[VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html),
[subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html)
and [VCN get](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html).
Root-only subtree enumeration uses ACCESSIBLE and ACTIVE, adding root once.
Only READY subscriptions are included in all-region mode. A successful blank CLI
list is accepted only for known list commands, consistent with Oracle's
[3.94.1 CLI renderer](https://github.com/oracle/oci-cli/blob/v3.94.1/src/oci_cli/cli_util.py#L893-L947);
empty object gets remain invalid.

## Verification

Toolchain: macOS 26.7.1 Apple Silicon, Xcode 27.0 (27A266a), Flutter 3.47.7,
Dart 3.13.5, OCI CLI 3.94.1. Native dependencies use Swift Package Manager.
Machine-specific SDK paths are not tracked.

v0.3.0 package and widget verification completed; native packaging is pending:

- Core: 50 tests passed; analyzer clean.
- Data/imports: 78 tests passed; analyzer clean. New fictional multi-region tests
  verify regional identities and parents, atomic apply, repeat refresh retaining
  local fields/absent regions, rollback for an invalid later record, and visible
  same-domain overlap across regions.

- OCI adapter: 83 tests passed; analyzer clean, including all scope combinations,
  root/region deduplication, pagination, regional context, READY exclusions, empty
  results, late required failures, cancellation and single/broad deadlines.
- CLI: 49 tests passed; analyzer clean, including pre-connection scope validation,
  repeated/comma-separated regions, all-scope flags, help and no partial writes.
- Flutter: 71 widget tests passed; analyzer clean, including GUI scope combinations,
  busy controls, broad empty retry, copyable help and responsive planner/reservation.

All 331 package/widget tests passed. The planner's 390/780/1100/1440 pixel widget
layouts retain controls and reservation access; wide views put the map above the
fold. Current validation uses fictional runners and isolated temporary/memory
stores; it does not collect a live tenancy or change the user's default inventory.
Native build, packaging and independent review remain pending.

## Release status

The latest published preview is [v0.2.1](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.1).
Its universal DMG is 21,024,500 bytes, SHA-256
`bf8818d8364ad3cfffd5b8de44cc1b726b99b195a3e339c4f4a1615d2df8ece8`.
The [v0.2.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.0)
and [v0.1.0](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0)
assets are preserved. v0.3.0 will be published after verification of its own build.

`scripts/build_macos.sh`, `build_cli.sh` and `build_dmg.sh` build the universal app,
current-platform CLI and verified DMG. Packaging checks both architectures,
deep/strict signature integrity, read-only mounted contents and SHA-256.
Signing is ad hoc; no Developer ID signature or notarization ticket exists. Local
verification does not establish Gatekeeper acceptance on another Mac. The app has
App Sandbox disabled for local CLI process access and shared app/CLI storage.

## Next actions

Finish v0.3.0 verification and publish the private universal DMG/checksum. Then
scope the observed connectivity collector and topology model. Wider distribution
requires Developer ID signing and notarization. Keep customer data, credentials,
databases, generated builds and machine-specific SDK paths out of Git.
