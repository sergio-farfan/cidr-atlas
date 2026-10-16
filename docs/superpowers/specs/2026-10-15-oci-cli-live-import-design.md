# CIDR Atlas — OCI CLI live inventory import

Date: 2026-10-15
Author: Sergio Farfan <sergio.farfan@gmail.com>
Status: Approved by Sergio Farfan on 2026-10-15

## Intent and agreed decisions

Retrieve live OCI network inventory into CIDR Atlas without requiring manual JSON
exports. The user selected an existing OCI CLI profile, with region and
compartment selection. Keep the existing Flutter UI, pure Dart engine, and local
SQLite architecture. The source is maintained in the verified private GitHub
repository [sergio-farfan/cidr-atlas](https://github.com/sergio-farfan/cidr-atlas).
No inventory or credentials belong in that repository.

## Approved first-version scope

Collect VCNs and subnets for one explicitly selected region and compartment per
run. The compartment picker shows accessible compartments and the tenancy root;
selecting a parent does not implicitly collect descendants. A routing domain is
required separately, because tenancy and compartment do not define connectivity.
The workflow reads OCI and writes only the local inventory after an explicit
Apply action. It makes no OCI changes, schedules no background scans, and creates
no new credentials or browser authentication sessions.

The profile, region/compartment selection, repository, and complete design are
approved. The following sections define the implementation requirements.

## Desktop workflow

Keep the existing offline import workflow. Add an OCI CLI entry to its import
dialog so the current toolbar fits both supported desktop widths. The live
dialog follows this sequence:

1. Locate an existing `oci` executable and local configuration file. Show a
   useful setup error when either is unavailable; never install tooling silently.
   Check PATH and the standard macOS Homebrew locations, and allow an explicit
   executable/config path override. Paths remain local and are not exported.
2. Show profile names, then the profile's tenancy identifier and default region.
   Read only configuration metadata needed for selection; retain no raw config,
   private keys, passphrases, or token contents. Resolve DEFAULT inheritance.
   Select API-key or security-token authentication explicitly, with an initial
   suggestion based on profile metadata. OCI CLI reads its own credential files.
3. On an explicit Load scopes action, list subscribed regions and accessible
   compartments. Enable collection for READY regions. Include a clearly named
   tenancy-root entry derived from the profile tenancy OCID. Permit a manually
   entered region and compartment OCID when IAM prevents selector enumeration;
   resource-list requests remain the authority on access.
4. Require region, compartment, and routing domain before Discover. Show progress
   and Cancel while collecting; keep the UI responsive.
5. Present the existing import review, including fetched prefix counts, validation
   errors, conflicts, coverage warnings, collection interval, and referenced VCN
   context. Cancel discards it. Apply uses the existing atomic import transaction.

Use existing visual styles and responsive constraints. Missing/expired credentials
produce an actionable error directing the user to repair their CLI profile;
there is no automatic login or interactive subprocess prompt.

## Collector boundary and command contract

Add a pure Dart `packages/cidr_oci` adapter shared by the desktop UI and CLI. It
owns executable discovery, allowlisted profile metadata, selector calls,
subprocess lifecycle, progress, cancellation, and OCI bundle output. `cidr_data`
continues to own normalization, identity reconciliation, and SQLite writes.
Neither shared package imports Flutter.

Each subprocess uses an executable plus an argument list with `runInShell: false`.
Consume both output streams. The adapter exposes an injectable process runner and
clock for deterministic tests. Give each request a bounded timeout and the whole
collection an overall timeout; exact durations and progress wording remain
implementation choices. Cancellation/timeout terminates the current child, drains streams,
and produces no applicable result. No raw stdout, credential-bearing environment,
or verbose/debug CLI output is logged.

Use an explicit configuration, profile, authentication mode, region, and JSON
output for each OCI command. Isolate CLI rc defaults and inherited OCI endpoint,
query, filter, and authentication overrides so they cannot silently redirect or
filter the selected scope. Preserve normal OS execution and TLS trust settings.
Use a bounded CLI retry policy without adding a second retry loop in Dart.

The verified command suffixes are:

| Purpose | Arguments after explicit connection options |
| --- | --- |
| Regions | `iam region-subscription list --tenancy-id TENANCY --all` |
| Compartments | `iam compartment list --compartment-id TENANCY --compartment-id-in-subtree true --access-level ACCESSIBLE --lifecycle-state ACTIVE --all` |
| Selected VCNs | `network vcn list --compartment-id COMPARTMENT --all` |
| Selected subnets | `network subnet list --compartment-id COMPARTMENT --all` |
| Missing referenced VCN | `network vcn get --vcn-id VCN_OCID` |

Do not add `--limit`, display-name, lifecycle, or VCN filters to the two resource
lists. Selecting the root still collects only resources directly in the root.
Do not use `--include-root` for the compartment picker: the installed CLI performs
an extra GetCompartment request which can fail under constrained IAM.

## Coverage and failure behavior

Both selected-compartment resource lists must succeed, return valid JSON, and
complete all pages before producing a usable preview. A required-list failure,
malformed result, cancellation, or timeout leaves SQLite untouched and disables
Apply. An empty discovery does not delete, retire, or release existing records.

Subnets can live in another compartment than their VCN. Deduplicate missing
subnet VCN references and fetch those VCNs by ID as context. Explain any context
from outside the selected compartment in the preview, and do not enumerate that
VCN's other subnets. A denied/not-found context lookup is a visible warning;
retain the subnet's `vcnId`, omit a fabricated `parentId`, and let existing import
validation/reconciliation decide applicability. NotAuthorizedOrNotFound is not
proof of deletion. Cancellation or malformed successful context output still
fails the collection rather than quietly producing corrupt context.

The bundle contains `metadata.tenancy`, `region`, `collectionStartedAt`,
`collectedAt` (completion UTC), a coverage description, and `vcns`/`subnets` arrays.
Coverage identifies the exact compartment and region, all-page collection,
context successes/failures, and the observation interval. It explicitly states
that this is a scoped observation collected over time, not a transactionally
consistent tenancy snapshot or a complete tenancy audit. Do not substitute
resource creation time for observation time.

## Import and data integrity

Pass the bundle through `InventoryImport.json`, with the explicitly chosen routing
domain and current records. Preserve its `ImportPreview.source == 'OCI JSON'` and
incoming record source `oci`: current merge protections depend on those values.
Use `mergedImportRecords` for preview and `applyImport` for commit. Preserve local
owner, environment, status, notes, customer, and explicit hierarchy; never infer
that omitted resources are free. Real discovered overlaps remain visible.

Extend CIDR normalization to include subnet `ipv4-cidr-blocks`/`ipv4CidrBlocks` and
VCN `byoipv6-cidr-blocks`/`byoipv6CidrBlocks`, deduplicated with existing aliases.
Every distinct CIDR remains its own prefix record with shared resource identity.
Keep actual resource/compartment IDs and subnet VCN IDs. Continue exact CIDR and
host-bit validation, routing-domain isolation, and explicit relationship rules.

## Desktop CLI

Add `cidrctl discover oci` using the same collector, with explicit `--profile`,
`--region`, `--compartment-id`, and `--routing-domain`; support configuration,
executable, and authentication overrides. It previews by default. `--apply`
performs the same atomic import. Preserve existing exit-code meanings for usage,
collection/storage failure, and successful preview/apply. Document scope and
coverage, and keep existing offline commands compatible.

## Verification and completion

Test profile inheritance and secret omission; exact argument/environment scope;
pagination flags; missing tooling and expired-auth errors; cancellation/timeout;
required-list failures; cross-compartment VCN context and denied context; the new
IPv4/BYOIPv6 aliases; atomic writes; preserved planning metadata; absence retention;
routing-domain reuse; and multiple CIDRs/resource identities. Use fictional CLI
fixtures and injected runners for automated tests. Widget tests cover selection,
progress, failed collection, preview/apply, and narrow/wide layouts. CLI integration
tests cover preview defaults and explicit apply against temporary databases.

Run package formatting/analyzers/tests, Flutter analysis/widget tests, and native
macOS/CLI builds. Verify the UI against installed OCI CLI 3.94.1. A live request
requires the user-selected existing profile and explicit scope; keep any observed
customer inventory outside the repository. If credentials or IAM prevent a live
smoke check, report it precisely rather than weakening the tests or importing a
partial result. Update PROJECT.md with actual verification and remaining work.

## Documentation evidence

Command flags were cross-checked against installed OCI CLI 3.94.1; current online
CLI documentation identifies 3.95.0. Model fields were also checked against the
installed Oracle Python SDK 2.187.1.

- [OCI configuration and profiles](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm)
- [OCI CLI option precedence](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clienvironmentvariables.htm)
- [CLI rc configuration](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm)
- [Session-token authentication](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm)
- [Subscribed regions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html)
- [Accessible compartments](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html)
- [VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html)
- [Subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html)
- [VCN get](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/get.html)
- [OCI pagination](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/usingapi.htm#nine)
- [Subnet compartment selection](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/create_subnet.htm)
- [Independent subnet moves](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/move_subnet_compartment.htm)
- [VCN fields](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/core/models/oci.core.models.Vcn.html)
- [Subnet fields](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/core/models/oci.core.models.Subnet.html)
- [OCI API errors](https://docs.oracle.com/en-us/iaas/Content/API/References/apierrors.htm)
- [Dart subprocess API](https://api.dart.dev/dart-io/Process/start.html)
