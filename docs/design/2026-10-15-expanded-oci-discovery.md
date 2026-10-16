# CIDR Atlas — Expanded OCI discovery

Author: Sergio Farfan <sergio.farfan@gmail.com>

## Purpose

Build a local inventory across selected regions or all READY subscribed regions,
and one direct compartment or all accessible active compartments and descendants,
without repeating manual imports. Preserve existing profiles, offline imports,
preview, atomic apply, planning metadata, and discovered conflicts.

## Scope and collection

`OciInventoryClient.discover(connection, {List<String> regions = const [],
bool allRegions = false, String? compartmentId, bool allCompartments = false,
OciCancellation? cancellation, void Function(String)? onProgress})` requires
exactly one region mode (nonempty selected regions, or allRegions) and one
compartment mode (nonblank compartmentId, or allCompartments). Copy, trim and
deduplicate explicit regions; reject blanks and conflicting modes before requests.

All-region mode freshly enumerates subscriptions and selects READY entries only;
report other statuses and fail when none are READY. All-compartment mode freshly
lists root tenancy with subtree true, ACCESSIBLE, ACTIVE and all pages, then adds
the root once. Enumerate compartments once, then collect VCN and subnet lists for
each region/compartment pair sequentially, each with --all. Progress identifies
region, compartment and scope count. Collect all regional lists before resolving
missing VCN context; fetch missing context once per region/resource identity.
Stamp each resource with its actual query region. Single-region metadata retains
region; multi-region metadata omits that scalar and records the region list.

Required enumeration/list failures, malformed responses, cancellation and timeout
return no bundle. Errors identify the failing operation and scope without raw CLI
output. Denied/not-found referenced VCN context remains a warning. Each command
retains its 60-second bound; collection defaults to 180 seconds for a single pair
and 1800 seconds for broader modes, with injectable deadlines for tests.

Coverage records region/compartment modes, actual regions and compartments,
completed pairs and resource counts, interval, and context outcomes. Accessible
compartment enumeration does not guarantee network permission or visibility of
IAM-hidden compartments. A successful run is an observation, not a complete,
transactionally consistent tenancy audit; omission never proves deletion/free IPs.

## Interfaces

The GUI retains one selected region by default, supports adding READY regions and
all READY mode, and offers an independent all-accessible-compartments option.
Manual mode accepts comma-separated regions and one compartment OCID; broad modes
remain explicit. Hide or disable replaced selectors. Disable scope/help controls
while collection is active. One result returns to the existing import preview.
Empty broad results explain region, permissions and inventory coverage without
instructing the operator to enter a CIDR or choose an already-included child.

CLI uses repeatable/comma-separated --region or --all-regions, and
--compartment-id or --all-compartments. Conflicting or missing dimension choices
are usage errors before configuration/database access. Profile and routing domain
remain required. Preview is the default; --apply uses the same atomic import.

## Planner layout

Make the central address map the main workspace with compact controls and a
selected-network inspector. Clearly label address hierarchy and available space;
containment is not observed connectivity. Route/DRG/gateway/peering topology needs
additional typed collection and is outside this release. Preserve calculation,
conflict checking, keyboard access and small-window scrolling.

## Validation and delivery

Use fictional runner fixtures and widget tests, never a live tenancy inventory,
for matrix traversal, region identity, IAM failures, cancellation, empty results,
CLI validation and UI behavior. Verify cross-region preview/apply and refresh
preserve identities, hierarchy, local metadata and absent records. Run package
analyzers/tests and Flutter widget tests. Build and verify a universal macOS DMG
and standalone CLI, publish a new private prerelease, and preserve older assets.
No default user database is modified by validation. Ad hoc signature does not
establish Developer ID signing or notarization.

## Oracle references

Validated against installed OCI CLI 3.94.1 help and official references:

- [Compartment list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html): subtree true requires tenancy root; ACCESSIBLE is INSPECT visibility, not network-list authority.
- [Region subscriptions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html): tenancy subscriptions, all-page retrieval.
- [RegionSubscription](https://docs.oracle.com/en-us/iaas/tools/python/latest/api/identity/models/oci.identity.models.RegionSubscription.html): READY and IN_PROGRESS states.
- [Managing regions](https://docs.oracle.com/en-us/iaas/Content/Identity/Tasks/managingregions.htm): global IAM and regional VCNs.
- [VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html), [subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html): direct compartment resource calls and pagination.
