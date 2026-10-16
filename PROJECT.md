# CIDR Atlas — implementation status

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Product direction

Local-first CIDR inventory and allocation planning for an enterprise OCI architect. The macOS Flutter application, pure Dart domain engine, SQLite store, and desktop CLI share the same rules. Offline CSV/JSON imports and explicit read-only OCI CLI discovery both provide validation previews and atomic local apply. iOS, Windows, and Linux graphical releases remain future milestones; team/device synchronization requires a central authority.

## Current implementation

The approved visual address-planning milestone is implemented for v0.2.0, alongside the existing inventory, conflict review, history, editor, address checker, imports, and exports. New installations start empty; optional demo data and examples are fictional.

- **Visual planner:** explicit routing-domain and allocation/VCN pool selection, manual pool boundaries, allocation hierarchy, grouped OCI VCN CIDRs, known subnet relationships, unresolved context, conflict indicators, and a proportional free/blocked address map. Candidate selection, keyboard navigation, zoom, fit/reset, and responsive details support the established desktop sizes. Presentation filters do not remove allocation blockers.
- **Shared CIDR inspector:** canonical prefix, family, prefix/host bits, IPv4 mask, exact address total and range, child-slot counts, and an explicitly selected containing supernet. The same domain calculations serve the GUI and CLI.
- **Demand and recommendations:** choose a prefix or size an OCI IPv4 subnet from current/peak demand, an explicitly chosen growth percentage, and separate additional demand. Exact free-address and aligned-slot totals are independent of the bounded candidate list. Ranking favors the smallest fitting aligned free block and edge placements; it is an allocation heuristic. The app shows up to 12 candidates.
- **Local reservation:** the GUI opens a reviewable editor; CLI `recommend` previews by default and requires explicit apply and a name. Both retain sizing/placement rationale in notes and reject duplicate identity or stale conflicts inside the SQLite write transaction. Changes to planning inputs or inventory invalidate GUI results. OCI refresh preserves planning metadata and never frees absent observations.
- **CLI:** the source launcher and native executable retain existing inventory/import/export operations and expose the shared recommendation engine through text or JSON output. Exact address/slot integers are decimal strings in JSON. Preview writes no inventory or history records, although opening a new database path can create the file.

Availability means **available within the supplied inventory and routing domain**. Partial coverage, unimported connected networks, and stale observations limit that conclusion. Prefix ancestry and validated OCI VCN/subnet membership are the relationships shown today. Observed routes, gateways, DRG/hybrid connections, and endpoint reachability require the later connection-collection/storage milestone.

OCI IPv4 subnet policy is restricted to `/16` through `/30` and subtracts the three provider-reserved addresses. Generic `/31` and `/32` remain valid arithmetic inputs. IPv6 totals and aligned slots use exact integers; a definitive OCI IPv6 assignable-host count is withheld because Oracle's current [IPv6 comparison](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ipv6.htm) and [VCN/subnet overview](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm) differ. Growth remains an explicit planning choice, consistent with Oracle's [network sizing guidance](https://docs.oracle.com/en/solutions/oci-best-practices-networking/identify-vcn-topology-and-specifications1.html).

## OCI discovery and diagnosed empty-list failure

`packages/cidr_oci` is a pure Dart adapter with no Flutter, SQLite, or inventory writes. The app and CLI use an existing OCI CLI profile, explicit authentication, region, compartment, and routing domain. Opening the app's discovery dialog reads allowlisted profile metadata; **Load scopes** and **Discover inventory** initiate network requests. API-key/security-token selection, configuration/executable overrides, READY regions, accessible compartments/root, and manual scope entry are supported. Key/token-file access remains inside the OCI CLI process.

Each discovery collects all VCN and subnet pages directly in one selected compartment and region. It does not traverse descendants. Missing referenced VCNs are fetched once by ID as relationship context without collecting their other subnets. Missing/denied context is a visible coverage warning. Required-list failures, malformed responses, cancellation, and timeouts prevent an applicable partial discovery. Per-request and complete-collection deadlines are 60 and 180 seconds, followed by bounded child cleanup. Offline imports remain available without OCI tooling or network access.

An explicitly authorized, scoped read-only live check reproduced the v0.1.0 failure: the VCN list succeeded with blank stdout, which the adapter incorrectly treated as malformed JSON. The adapter now accepts successful empty stdout only for its known list commands; empty object-get output remains invalid. Malformed-response diagnostics name the operation and expected structure without exposing raw response contents. Repeating the same selected scope after the fix returned zero VCNs and zero subnets, with a direct-compartment/child-compartment warning. This result does not describe descendant compartments or establish resource deletion.

Actual allowlisted configuration metadata was read and live OCI requests occurred during that authorized check. It performed no OCI writes or local inventory writes. Automated tests and controlled executable smoke checks used fictional data. Profile names, tenancy/resource identifiers, and live output are excluded from project artifacts.

Scope and pagination were checked against installed OCI CLI 3.94.1 and Oracle's [VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html), [subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html), and [VCN get](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html) references. The blank-output behavior matches the [Oracle CLI 3.94.1 implementation](https://github.com/oracle/oci-cli/blob/v3.94.1/src/oci_cli/cli_util.py#L893-L947). Profile/authentication conventions follow Oracle's [configuration](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm) and [token authentication](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm) documentation.

## Verification

Toolchain: macOS 26.7.1 on Apple Silicon, Xcode 27.0 (27A266a), Flutter 3.47.7 (`abaf9c5237`), Dart 3.13.5, and OCI CLI 3.94.1. Machine-specific SDK paths remain outside source. Current native plugins use Swift Package Manager.

| Area | Verified result |
| --- | --- |
| Core | 50 tests passed; analyzer and formatting clean |
| Data/imports | 50 tests passed; analyzer clean, including persisted rationale, OCI refresh retention, and transaction-time stale-reservation rejection |
| OCI adapter | 63 tests passed; analyzer clean, including successful empty lists and safe malformed-response diagnostics |
| CLI | 44 tests passed; analyzer and formatting clean; 15 recommendation cases extend existing inventory/import/discovery coverage |
| Flutter | All 45 integrated widget tests passed; analyzer clean, including protected recommendation identity and imported OCI subnet capacity |
| Native macOS | Release app build succeeded at 44.7 MB with `arm64` and `x86_64`; standalone CLI compiled for `arm64` |

Core coverage includes IPv4 `/0`, `/31`, `/32`, IPv6 `/0` and `/128`, exact large integers, domain reuse, explicit hierarchy, nested/overlapping interval unions, partially occupied aligned slots, fragmentation, no-fit, growth rounding, and deterministic bounded recommendations. The demand example of 100 addresses plus 20% growth plus four additional addresses requires 124 assignable addresses and selects an OCI `/25` with 125 assignable addresses.

The compiled CLI passed fictional temporary-database checks for preview without record/history writes, explicit reservation, saved rationale, reopen/export, occupied-candidate rejection, no-fit, and invalid inputs. Existing controlled discovery checks cover preview/apply, failed collection preserving state, and SIGINT child cancellation. Shared data tests verify the two-connection stale-candidate case. Widget coverage includes explicit scope, hierarchy, conflict/coverage indicators, keyboard selection, stable zoom, input/inventory invalidation, inspector output, and 1100×740 / 1440×900 layouts.

All 252 package/widget tests passed. Nonmutating formatting checked 44 maintained Dart files with zero changes. Independent scoped reviews and the final integrated review found no remaining blockers after correcting recommendation resource-identity protection and consistent OCI capacity in the planner inspector.

Earlier native checks established fictional CSV preview/apply, shared app/CLI persistence, JSON export, and empty-state restoration. The v0.2.0 release app launched with an empty inventory. A fictional manual `/8` preview rendered the address map, bounded candidates, CIDR details, and exactly 65,536 available `/24` slots; the CLI confirmed zero local records and no history afterward. Current reservation/editor, responsive layouts and imported OCI capacity have widget coverage; a new native reservation/apply cycle and broader native file-dialog checks remain additional verification. Earlier Linux checks establish baseline portable package behavior and a Linux CLI build; they do not establish current Windows/Linux collector behavior or graphical packaging.

## Release status

The private [source repository](https://github.com/sergio-farfan/cidr-atlas) and published [v0.1.0 preview](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.1.0) remain available. The v0.1.0 universal DMG and checksum are unchanged; that release does not contain the visual planner or empty-list fix. Publication of the approved [v0.2.0 release](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.2.0) is pending.

`scripts/build_dmg.sh` packages the universal application with an Applications shortcut, installation instructions, and third-party notices under `build/releases/`. The final v0.2.0 app was built from a clean Flutter/Xcode output after an incremental build left a stale outer signature. The clean build and DMG passed deep/strict signature checks, both architecture checks, image verification, read-only mounting, mounted-app checks, expected-content inspection, detach, and checksum validation. The final image is 20,959,049 bytes; SHA-256 is `ecf43fd4011849d5c4f960d288bc0838954e19c7ca264e614c948f2de827d39b`. Uploaded-asset confirmation is pending. The standalone CLI is built separately.

Signing is ad hoc. No Developer ID signature or Apple notarization ticket exists, and local verification does not establish Gatekeeper acceptance on another Mac. The app currently has App Sandbox disabled to share the local database with the CLI. Apple documents disk-image packaging in the [Disk Utility guide](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac); installed Apple command help defines the script's flags.

## Next actions

Complete private v0.2.0 asset publication. For useful live inventory, explicitly select the compartment that actually contains the intended resources and review discovery coverage before any local Apply. Subsequent product work is the separately scoped observed-connections collector/storage contract; wider macOS distribution also requires Developer ID signing and notarization. Additional native reservation and file-dialog checks can extend the current automated and baseline verification.

Keep credentials, customer inventories, generated builds, databases, and machine-specific SDK paths out of Git.
