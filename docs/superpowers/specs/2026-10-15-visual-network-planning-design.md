# CIDR Atlas — Visual Network Planning and CIDR Recommendations

Author: Sergio Farfan <sergio.farfan@gmail.com>
Date: 2026-10-15
Status: Proposed scope for review; implementation has not started

## Intent

Help a cloud or network administrator choose an appropriate available CIDR,
avoid conflicts, and use address space efficiently while allowing deliberate
growth. Combine a visual address plan, calculated CIDR details inspired by the
supplied calculator screenshot, and an explainable recommendation workflow.
Network relationships and eventual observed connections belong beside the
address plan, with their evidence visible.

Keep Flutter, the pure Dart engine, local SQLite, the desktop CLI, and both
offline CSV/JSON and explicit OCI CLI imports. No automatic cloud changes or
background collection are introduced.

## Research informing the proposal

Community requests emphasize expandable prefix hierarchy, inline capacity,
retaining navigation context, selectable relationship layers, stable layouts,
and useful editable exports. These are recurring themes in a small sample of
discussions, not a representative survey:

- [NetBox hierarchical IPAM request, January–June 2026](https://github.com/netbox-community/netbox/discussions/21255)
- [Topology relationship layers and saved positions, December 2025](https://github.com/netbox-community/netbox-topology-views/issues/686)
- [Stable topology layout, 2025–2026](https://github.com/netbox-community/netbox-topology-views/issues/634)
- [Connection metadata in editable export, April 2025](https://github.com/netbox-community/netbox-topology-views/issues/624)
- [Administrator discussion of automated diagrams, July 2024](https://www.reddit.com/r/networking/comments/1ec3u10/automating_network_diagrams/)

Oracle recommends planning for future expansion, avoiding overlap with connected
networks, using workload-appropriate subnet sizes, and preserving contiguous
addressing that simplifies routing. Services can consume multiple IPs, and
disaster recovery adds capacity requirements. These are policy inputs rather
than a universal percentage or a mandate to allocate the smallest possible block.
[Oracle sizing guidance](https://docs.oracle.com/en/solutions/oci-best-practices-networking/identify-vcn-topology-and-specifications1.html),
[Oracle connectivity and expansion guidance](https://docs.oracle.com/en/solutions/oci-best-practices/define-your-network-and-connectivity-architecture1.html)

## Delivery sequence

The proposed first milestone is **Address Space and CIDR Recommendations**:
visual allocation hierarchy, open slots, the shared CIDR inspector, sizing from
address demand, ranked candidates, and explicit local reservation. The existing
inventory supports this milestone without new live network calls.

The following milestone is **Observed Connections**: import and persist typed
topology resources and relationships, then show routes, gateways, DRG attachments,
and supported hybrid connections. It requires a separate collection/storage
contract. Oracle-native topology endpoints should be evaluated before adding a
large manually assembled collector. This proposal does not claim that existing
prefix records already describe connectivity.

## Address Space workspace

Add a Network workspace with an Address Space view and a resource hierarchy.
Keep the existing planner's workflow accessible through this workspace. Selecting
a routing domain and an explicit allocation or VCN pool defines the planning
boundary. Region, tenancy, compartment, name, status, and environment can further
filter the view, but filters must not remove blockers from allocation checks.

The left side provides an expandable allocation/VCN/subnet hierarchy. One OCI VCN
resource appears once with its multiple IPv4/IPv6 CIDRs. The center provides a
stable, ordered address map with occupied ranges and aligned candidate slots.
The right side presents the selected CIDR and recommendation details. At narrow
desktop widths, use an accessible details dialog or drawer.

Use distinct labels and patterns as well as colors for active allocations,
reservations, plans, conflicts, retired entries, and candidate space. Show a
coverage/freshness banner when the source is incomplete or old. The useful label
is "Available in this inventory"; missing cloud resources are not proof that
space is free.

Selecting a child prefix size updates exact slot counts and the highlighted
slots. Render a bounded page or zoom window and report the actual total, such as
"12 shown of 37 candidates." Never enumerate all IPv6 addresses or all possible
child prefixes. A selected open slot can be inspected, copied, or reserved.

"Newly available" means a comparison against a defined previous inventory state
and an explicit release/retirement event. Until that baseline is implemented,
highlight current candidate slots without claiming that they are newly freed.
Discovery omissions continue to retain existing reservations and observations.

## CIDR inspector

Use the same inspector in the inventory, address map, and recommendation results.
The supplied screenshot informs the details, with precise field names:

| Field | Meaning |
| --- | --- |
| Network prefix | Canonical network CIDR; this does not assert an installed route |
| Prefix length | Network bits and remaining host bits |
| Subnet mask | Dotted IPv4 mask; IPv6 uses prefix notation |
| Address range | First and last address, both formatted |
| Total addresses | Exact mathematical capacity |
| Provider capacity | Separately documented assignable capacity when known |
| Child subnet size | Selected target prefix and exact total/free slot counts |
| Containing supernet | Calculated for an explicitly selected shorter prefix |
| Ownership and state | Parent, domain, status, owner, environment, and notes |
| Evidence | Source, observation time, collection scope, and unresolved context |

Replace the ambiguous "Max Supernets" label with "Containing supernet." A
calculated supernet does not authorize allocating its entire range. Retain strict
host-bit rejection on any reservation input.

For IPv4 address width 32 and IPv6 width 128, total addresses are
`2^(addressWidth - prefixLength)`. A parent `/p` contains `2^(q - p)` aligned
child slots of `/q` before blockers, for `p <= q <= addressWidth`.
Use exact integers and interval unions. Nested and overlapping records must not
be double-counted; fragmented free addresses do not necessarily form an aligned
block of the requested size. [CIDR semantics, RFC 4632](https://www.rfc-editor.org/rfc/rfc4632.html)

OCI documents IPv4 subnet sizes `/16` through `/30`, with three reserved
addresses per subnet. The usable capacity of an eligible IPv4 subnet is its
total minus three. Generic `/31` and `/32` calculations remain distinct from OCI
subnet eligibility. Do not subtract subnet overhead from an entire VCN pool.
[Oracle addressing comparison](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ipv6.htm),
[Oracle IPv4 reservation examples](https://docs.oracle.com/en-us/iaas/Content/Compute/References/bestpracticescompute.htm)

Oracle's current IPv6 comparison and general VCN/subnet overview disagree about
the number of reserved IPv6 addresses. The first milestone shows exact IPv6
total capacity and `/64` subnet slots, but does not publish a definitive OCI IPv6
assignable-host count until that discrepancy is resolved. Generic IPv6 has no
broadcast-address subtraction. Address capacity also does not imply that service
quotas or per-resource limits permit creating that many objects.
[Oracle IPv6 comparison](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ipv6.htm),
[Oracle VCN/subnet overview](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm),
[IPv6 addressing, RFC 4291](https://www.rfc-editor.org/rfc/rfc4291.html)

## Recommendation inputs and sizing

Offer two modes: **Choose by prefix** and **Size from address demand**. Preserve
manual prefix choice for VCN/allocation planning. Automatic host-demand sizing
initially targets OCI IPv4 subnets; a VCN must be planned from its child subnet
requirements rather than treating every address as an assignable host.

Required inputs are the selected pool, routing domain, resource kind, address
family, and either requested prefix or address demand. Identify demand as current
or already planned peak demand; do not silently add growth twice. Host-demand sizing also
shows an explicit growth allowance and fixed additional IP demand for service,
HA, upgrade, or DR needs. Growth may be zero only by deliberate selection. Do
not silently assume that one VM consumes one IP, or double-count service demand
already included in the main input. The first milestone accepts these counts
directly; workload-specific OKE/load-balancer estimators need separately verified
models and are outside this milestone.

There is no universal growth percentage in the cited Oracle guidance. A saved
organizational policy or explicit administrator choice supplies that number.
For base demand `D`, percentage growth `g`, and separate fixed demand `H`, the
target is `ceil(D * (100 + g) / 100) + H`. Choose the most specific legal prefix
whose provider capacity meets the target, constrained by the selected parent.
If no allowed block fits, say so rather than reducing the required capacity.

Illustrative example: 100 endpoint IPs, an explicitly chosen 20% growth
allowance, and four additional maintenance IPs require capacity for 124 IPs. An OCI
IPv4 `/25` provides 128 total and 125 assignable addresses; `/26` is too small.
Show 124 planned-capacity units and one remaining beyond the chosen allowances.
These are planning counts, not observations of deployed or unused IPs.

## Candidate selection and reservation

1. Validate the inventory, parent relationship, family, requested size, and policy.
2. Consider every relevant blocker in the explicit routing domain, including
   planned and reserved networks and imported on-premises/other-cloud prefixes.
   Validated ancestors are handled by the existing hierarchy rules.
3. Compute disjoint free intervals and aligned candidates, retaining partial
   blockers. A display filter never changes this check.
4. Rank a bounded candidate set by the requested sizing policy and efficient
   placement: prefer fitting smaller gaps while preserving larger aligned free
   blocks; use deterministic address order to break ties. This is a product
   allocation heuristic, not an Oracle-mandated algorithm or an optimal-packing
   guarantee. Leave the exact efficient scoring implementation to the builder.
5. Show the best recommendation and alternatives with capacity, growth, spare
   space, coverage, and placement explanations. Compare a smaller and larger
   prefix when useful; unavoidable power-of-two rounding is visible.
6. Reserve only after an explicit action. Recheck conflicts against current
   SQLite state inside the write transaction. A stale proposal that no longer
   fits must fail clearly without a partial reservation.

Do not promise conflict freedom beyond known inventory coverage. Do not create
OCI resources, infer a new routing domain, reclaim a missing observation, merge
unrelated prefixes, or change existing allocations to make a candidate fit.

## Network relationships and future connections

The first milestone may show explicit allocation ancestry and validated OCI
VCN/subnet membership. Label these relationships accurately. Source, time, and
scope are available on selection; unresolved parents remain visible.

For the later Connections view, evaluate Oracle's documented regional, VCN, and
subnet topology APIs through the installed CLI. Persist typed entities/edges,
service and collection times, permissions/limited entities, and unresolved
references separately from prefix records. Support offline topology snapshots
through the same preview-first principles. Planned connections require explicit
planning provenance rather than an observed-resource label.
[Oracle regional topology](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/view-network-topology-map.htm),
[VCN topology CLI](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn-topology/get.html),
[subnet topology CLI](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet-topology/get.html)

Configured associations and routes do not independently establish endpoint
reachability. That would require routing, cloud security filters, host firewalls,
and destination evidence. Saved views, relationship toggles, focused drill-down,
and later SVG/PNG/draw.io exports should preserve scope, legend, and observation
time. Export is subsequent work, not a requirement to complete the first
allocation milestone.

## Architecture and acceptance

Keep arithmetic, capacity summaries, candidate sizing/ranking, and explanation
data in `cidr_core`, without Flutter. The app renders the result. The CLI should
expose the same recommendation inputs/results. Persistence records the selected
planning inputs and decision with the reservation so its rationale survives
reopening. The builder may choose the smallest compatible versioned storage
extension; existing backups/imports must remain readable.

Acceptance includes exact IPv4/IPv6 boundary arithmetic; provider eligibility;
strict inputs; domain isolation; explicit hierarchy; all relevant blockers despite
filters; overlapping/nested interval unions; fragmentation; no-fit cases; rounded
growth; candidate ordering; exact totals beyond rendering limits; absent-resource
retention; transaction-time conflict recheck; persistence; keyboard access;
selection; zoom/reset; and the existing desktop sizes. Test first and final slot
boundaries and very large IPv6 spaces without address enumeration.

No credentials or real inventories enter examples or tests. New fixtures are
fictional. A new macOS DMG is produced and verified for the release that actually
implements this proposal. The published v0.1.0 DMG remains the verified OCI import
release and does not contain these proposed additions.
