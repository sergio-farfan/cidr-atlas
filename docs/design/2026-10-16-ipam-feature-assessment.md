# CIDR Atlas — IPAM feature assessment against Infoblox

Author: Sergio Farfan <sergio.farfan@gmail.com>

Date: 2026-10-16. Infoblox NIOS and Universal DDI IPAM capabilities were assessed for fit with CIDR Atlas, with the focus on OCI and CIDR planning. Bracketed references point to the numbered sources in section 5. Claims marked UNVERIFIED could not be confirmed on the cited page.

## 1. Scope

This assessment covers features that help an enterprise OCI architect plan, allocate, validate and reconcile IPv4/IPv6 CIDR space. That means VCNs, subnets, supernets and routing domains, held in a local-first, single-user tool. It assumes the AGENTS.md premises [R11]:
- local-first SQLite, with no live database sync;
- explicit routing domains;
- numerical containment does not imply hierarchy;
- refresh preserves planning fields;
- imports are previewed and applied atomically;
- no OCI connection unless the user asks for it (user-initiated `discover oci` already exists [R9][R1]; nothing runs in the background);
- multi-user work waits for a future team service.

**Out of scope:** DNS and DHCP serving or records, DNS views, lease handling, active network probing, host-level IP maps, RIR registration, and writing reservations back into a cloud.

**DDI-adjacent concepts that still matter for OCI CIDR planning:**
- **OCI reserved addresses.** Every IPv4 subnet reserves 3 addresses: network, default gateway and broadcast [O1]. For IPv6 the docs conflict:
  - ipv6.htm says a /64 subnet has "8 addresses in the subnet reserved by Oracle (first 4 and last 4)" [O3].
  - The VCN and subnet overview says "With IPv4 addresses and IPv6 addresses, the first two addresses and the last in the subnet's CIDR are reserved" [O41].
  - CIDR Atlas already treats this as unresolved [R2].
- **Ranges that cannot be used in a VCN:** 169.254.0.0/16, Class D (224.0.0.0/4) and Class E (240.0.0.0/4) [O1].
- **OCI secondary private IPs and private IP CIDR objects.** A VNIC holds 1 primary and up to 64 secondary IPv4 addresses. "A CIDR IP address cannot overlap with any other private IP objects, reserved or assigned" [O12].
  - These are the OCI counterpart of Infoblox fixed addresses and reservations, and they mark where host-level IPAM begins.
  - CIDR Atlas does not collect VNICs or private IPs [R8], so host utilization stays out of scope until there is an opt-in import (Tier 3).
- **Non-subnet CIDR consumers inside or next to a VCN:**
  - OKE pods/services CIDRs [O27][O29];
  - VLAN CIDRs for OCVS [O33];
  - BGP inside-tunnel /30-/31 (IPSec) [O24] and FastConnect /28-/31 peering link nets [O25];
  - the Exadata X8M/X9M/X11M interconnect block 100.64.0.0/10, which must not be used by the client or backup VCNs or by database clients [O34].

**Where Infoblox stands on OCI (reconciled across the research):**
- Universal Asset Insights added OCI discovery as Early Access on 2026-03-25 and GA on 2026-07-17 [U1].
- Its OCI configuration includes an "IPAM Discovery" destination toggle and a Federated Realm selector [A1].
  - How OCI VCNs and subnets map into Universal IPAM objects is UNVERIFIED: [A1] does not say.
  - The only documented mapping is for AWS: VPC to IP space, VPC CIDR to address block [A2].
  - The asset-type matrix and IP-space naming pages do not list OCI [A3][A4].
- NIOS vDiscovery supports VMware, OpenStack, AWS, Azure and GCP, with no OCI [N29].
- The Terraform `bloxone_cloud_discovery_provider` documents AWS, Azure and GCP only [G10]. The federated realm `provider_type` is one of NIOS_X, NIOS, AWS, AZURE, GCP, MSAD [G8].
- OCI's own IP Address Insights is read-only. It offers no pools, allocation or policy [O37][O40]. Its CLI group has only these commands:
  - `get-resource-ip-inventory`
  - `get-subnet-cidr-utilization`
  - `get-subnet-ip-inventory`
  - `get-vcn-overlap`
  - `list-ip-inventory`

## 2. Fit-gap matrix

Fit values: **adopt** (copy largely as is), **adapt** (take the concept and change it to fit the premises), **defer** (needs the team service or broader collection), **out of scope**.

| Infoblox capability (product) | What it does | CIDR Atlas today | Fit | Why (premise) |
|---|---|---|---|---|
| Network views (NIOS) [N1][N2]; IP space (UDDI) [G1][U4]; Federated Realm [U2][G8] | A routing domain or namespace. Overlap is allowed between views or spaces. A realm is "a connected routing domain" [U2]. | `routingDomain` is a string on every record, compared after trimming. Overlap checks run per domain and IP version [R4]. There is no domain object; `cidrctl` warns about unknown domains and suggests near matches [R1]. | adapt | Rule 2 already matches. The gap is a managed domain object (description, owner, connected domains). See T2.11. |
| Container/leaf hierarchy inferred from containment (NIOS) [N3] | Creating a network that "belongs to a larger network" auto-creates a network container [N3]. | Explicit `parentId` or OCI VCN identity across three kinds (allocation, vcn, subnet). Containment alone never makes a parent [R1][R4]. | adapt | Rule 3 forbids inference. Borrow only the drill-down navigation and the lineage query (UDDI `/ancestor` [G11][G12]). |
| Same-CIDR container and network (NIOS 9.1) [N4] | A container and its network may share a CIDR. The docs contradict themselves on which is created first. | Separate records with explicit kind and parent [R1]. | adopt (test only) | OCI requires a subnet CIDR "within one of the VCN's CIDR block ranges" [O13]. An equal-CIDR VCN/subnet is inferred to be valid, though not stated explicitly. Add a regression test. |
| Next available network (NIOS GUI/WAPI [N5][N6][N7]; UDDI UI/API [U5][U7][G11]; Terraform [G5][G6][G16][G17]) | Free prefixes of size /x inside a parent: `num`/`count`, `exclude` list, parent picked by EA or tag filter. NIOS Add Networks caps at 20 per request [N5]. UDDI caps at 20 subnets ("The maximum number of subnets that can be created (N) is 20" [U7]), and the quantity field is "not applicable to IPv6" [U5]. | `InventoryRules.available()` (default limit 8) [R4]. `recommend` ranks aligned candidates (display limit 12); `--apply` reserves the first one through the store's strict reservation transaction [R1][R5][R9]. No count, exclude or tag-selected parent. | adopt (count, exclude); adapt (tag-selected parent) | The count and exclude lists fit as they are. Tag-selected parents need tags first (T2.3). |
| Concurrent next-available race (NIOS [N6], UDDI [U7]) | Concurrent users receive the same candidate; "The user who first saves the task gets" it [U7][N6]. | `reserve` re-checks identity, structure and conflicts inside the SQLite write transaction [R1][R6]. | do not adopt | Keep the stricter behavior. The service-era equivalent is a single allocation authority (rule 7). |
| Preview/commit split (UDDI GET vs POST next-available) [G11][G12] | GET lists candidates; POST allocates. | `import`, `discover` and `recommend` preview by default and write only with `--apply`. `check` is the dry run for `reserve`, which writes immediately [R9][R1]. | already present | Parity. |
| Network templates (NIOS) [N7][N5][N9] | A template sets netmask, attributes and nested range templates; a fixed netmask locks the size. | None. | adapt | Use as VCN or landing-zone blueprints, applied through preview and one atomic reserve (rule 6). Drop the DHCP content. |
| Extensible attributes: typed, list values, required (NIOS) [N10] | Types String, List, Integer, Email, URL, Date, plus a Required flag. "validation/enforcement of Required checkbox is done only in the Grid Manager"; WAPI and CSV can skip it [N10]. | Fixed fields: customer, tenancy, region, compartment, environment, owner, notes [R3]. | adapt | Enforce in `cidr_core`, so GUI, CLI and CSV share one check. The NIOS GUI-only gap is the anti-pattern. |
| Inheritable EAs (NIOS) [N11]; tag inheritance (UDDI) [U1] | States Inherited, Overridden, No Parent and others, with bulk descendant actions. | `recommend --apply` copies the parent's customer, tenancy, region, compartment, environment and owner once, plus the VCN OCID under a VCN parent [R1][R9]. | adapt | Inherit only along the explicit parent chain (rule 3). Never through containment. |
| Source vs local tags (UDDI) [U11][U1] | Source tags refresh on each discovery run ("removed if removed at the source"). User-added tags are "preserved across all subsequent discovery syncs" [U11]. | OCI tags are not ingested. The adapter keeps the raw resource objects [R8], but the importer reads only identity and CIDR fields [R7]. | adapt | Matches rule 5: keep local planning fields, refresh source attributes. |
| Smart folders (NIOS) [N12][N7] | Saved filters, grouping by EA, global or personal. | Search plus routing-domain and status filters only [R13]. | adapt | Personal saved views only. Shared folders need the service. |
| Utilization, container semantics (NIOS) [N13]; `allocation_v4` by state (UDDI) [G7][G8] | Container utilization is "the percentage of the total address space defined within the container", regardless of address use [N13]. UDDI breaks this down into allocated, delegated, reserved, overlapping and forward-looking-delegation % [G7]. | AddressSpaceSummary gives free and blocked intervals, address and slot counts and the largest free CIDR [R5]. No per-status breakdown or coverage %. | adopt | Fully computable offline from existing records. |
| DHCP/lease-weighted utilization (UDDI subnets [U4][U16]; NIOS networks [N13]) | Share of host addresses in use. | Not collected. | out of scope | Needs lease or VNIC data. Rule 9 keeps collection user-requested only. |
| Thresholds with trigger/reset (NIOS 95%/85% [N14][N15]); roll-up to ancestors (UDDI, 90% default [U4][U16]) | Alerts when a level is crossed, with hysteresis. "If you set the thresholds for an individual network, then it overrides settings at a higher level" [N15]. | None. | adapt | Show a visual flag in the planner and a CLI filter. No SNMP or email. |
| Prefix-length policy (UDDI) [U10]; federated block `network_compliance` [G7] | Min, default and max child prefix length. Create or resize requests outside it are "rejected". Pre-existing or discovered children "are not blocked" and get a trouble dot [U10]. | Only the OCI IPv4 subnet policy (/16-/30, 3 reserved) [R1][R5]. | adopt | Flagging imports instead of blocking them matches rule 6. |
| Reserved Block [G13][G14]; Forward-Looking Delegation (UDDI) [U9] | Holds space out of normal allocation, or earmarks it for a team before carving. Counted as reserved or FLD in `allocation_v4` [G7]. | Status `reserved` means a local allocation [R1][R3]. | adapt | Add a separate intent field. Do not overload `reserved`. |
| Delegation [U2] | Space delegated from a realm block to a participating IP space. | Explicit parent links [R1]. | already present (concept) | Rule 3 is the same idea. |
| Overlapping Block, sanctioned overlap (UDDI) [G9] | "an address range that may be managed independently by all participating IPAM services" [G9]. | The record editor's "Save with conflicts" keeps the overlap visible, but there is no waiver object [R13]. | adapt | Acknowledge the overlap but keep it listed (rule 6). Never suppress it. |
| Federated Block owner/authority (UDDI) [U2][G7] | Reserves a block and names the IPAM system that manages it, e.g. on-prem, GCP or another cloud. | On-prem and other-cloud supernets can already be entered as allocation records, but they look the same as OCI pools. | adapt | Add an explicit `external` intent and an authority field. |
| Split network (NIOS) [N16][N7] | Splits a network into N subnets in one pass, optionally inheriting EAs. | Planner reserves one candidate at a time [R10]. | adapt | Bulk-carve planned children only. A live OCI subnet cannot be split in place: a CIDR edit "must use the same network address as the previous range" [O13]. |
| Join/expand and resize (NIOS) [N17][N7]; unsupported when realms are assigned (UDDI) [U3] | Grows a network to a shorter prefix. | None. | adapt | OCI subnet edits must keep the same network address [O13]; VCN growth is done by adding a CIDR [O6]. Offer what-if checks, not mutation. |
| Container deletion policy and Recycle Bin (NIOS [N18][N19]; UDDI [U3][U7]) | Reparent or cascade on delete; restore from bin. UDDI next-available "does not search the Recycle Bin" [U7]. The WAPI default deletes children [N7]. | Deleting a record that still has children is refused. Status `retired` acts as a soft state [R1][R12]. | adapt | Keep refusing by default. Add a delete preview and a quarantine before retired space is reused. |
| CSV operations add/override/merge/delete (NIOS) [N21][N22] | Explicit per-row actions. | Id-matched rows merge only the supplied columns; atomic preview and apply [R1][R7]. | adapt | Map delete to retire; never hard-delete observed records (rule 5). |
| Non-atomic CSV import (NIOS) [N21][N20] | Stop or skip on error; no rollback. | Atomic [R1]. | do not adopt | Rule 6 makes this a differentiator. |
| Audit log (NIOS [N23]; UDDI, 13-month retention, CSV export [U14]) | Who, what and new values; per-object history. | `audit_entries(action, summary, at)` with paging; no actor, source, record id or field diffs [R6][R1]. | adapt | Add field diffs, source, reason or ticket, per-record history and export. |
| Approval workflows (NIOS 8.5) [N24] | Submitter and approver groups; ticket number. | None. | defer | Needs multiple users (rule 7). Locally, only a ticket field is worth taking. |
| Scheduled tasks (NIOS) [N25] | Executes changes at a set time. | None. | out of scope (as execution) | CIDR Atlas never provisions OCI. Translate into target and expiry dates on plans. |
| Admin permissions (NIOS) [N26]; Access Views (UDDI) [U15] | Default-deny, object-scoped RBAC. Next-available is limited to the parent CIDR of the access view [U1]. | Single user [R2]. | defer | Team service only (rule 7). |
| Unmanaged data and discovered-data merge policy (NIOS) [N8][N28][N27]; usage indicators IPAM vs DISCOVERED (UDDI) [G2] | Separates observed-only from managed data and converts unmanaged into managed. Merge (the default) appends new discovered data instead of replacing existing data [N27]. | `source=oci`, merged by stable id; refresh preserves planning fields [R1][R7]. No provenance state or adopt action. | adopt | Fits rule 5 and rule 6. |
| Stale asset soft/hard auto-delete (UAI) [U1] | Removes assets no longer reported after a retention period. | Never deletes or retires missing records [R1]. | do not adopt | Conflicts with rule 5. Use a "not observed since" flag instead. |
| Cloud discovery sync (UDDI AWS/Azure/GCP [U12][G10]; UAI OCI [A1]) | Periodic read or read-write sync. | User-initiated, read-only OCI CLI discovery across regions and compartments, fail-closed [R1][R8]. | already present (OCI-specific) | Rule 9: no background collection. |
| Net Map / IP Map (NIOS) [N13][N31][N8] | Graphical block map; per-address grid. | Visual planner address map with free, blocked, conflict and partial-space indicators [R10][R1]. | adapt (block map only) | Per-address grids are host-level and out of scope. |
| Address Space Perspective trends (UDDI) [U1] | Hierarchical view of blocks and allocations showing "utilization trends, fragmentation and overlap risk" (release-note excerpt). | Point-in-time summary only [R5]. | adapt | Capacity history from local snapshots (T2.17). |
| IPv6 next available (WAPI) [N7] | Same call works for IPv6. | Exact IPv6 arithmetic; no OCI IPv6 assignable-host policy [R1][R2]. | adopt | OCI IPv6 subnets are always /64 [O1][O3][O41]. The reserved count is disputed (3 vs 8), so keep it unresolved. |
| Filtered CSV export (UDDI) [U13] | Exports what the table shows, honoring filters. | CLI `list`/`export` honor filters; the app offers only "Export all" [R9][R13]. | adopt | Small UX gain. |
| Overlap summary monitor (UDDI) [U1]; Flat View overlap column [U4] | Count of overlapping blocks and overlaps per block. | Conflicts view in the app. `check` tests one candidate; there is no whole-inventory CLI conflicts command [R9]. | adopt | Scripting and review aid. |
| Copy block/subnet (UDDI API) [G11][G12] | Clones an object. | None. | adapt | Folds into templates (clone a plan into another domain). |
| RIR registration (NIOS) [N7] | RIPE registration status. | None. | out of scope | Private OCI planning; BYOIP is covered by an optional flag at most. |
| Cloud write-back (UDDI GCP internal ranges [U2]; AWS VPC IPAM scope authority [W4]) | Pushes reservations into the cloud allocator. | None. | out of scope | No OCI equivalent was found; OCI IP Address Insights is read-only [O37][O40]. Use IaC export instead (T1.8). |

**OCI-native gaps with no Infoblox equivalent.** All of these are sourced from docs.oracle.com:

| OCI fact | CIDR Atlas today | Fit |
|---|---|---|
| Remote peering: peers of one VCN "can't have CIDRs that overlap with each other", but "you aren't prevented by the Console or API operations" [O16]. LPG: spokes peered to one hub "can have overlapping CIDRs with each other" [O15]. A VCN attaches to "one and only one DRG" [O19]. | Topology is not modeled; connectivity is outside the current milestone [R1]. | defer (T3.1) |
| OKE flannel: VCN/subnets must not overlap pods or services CIDRs, and the Pods CIDR cannot change after creation. VCN-native: VCN/subnets must not overlap the services CIDR [O27]. Defaults are 10.244.0.0/16 and 10.96.0.0/16 for IPv4, fd00:eeee:eeee:0000::/96 and fd00:eeee:eeee:0001::/108 for IPv6 [O29]. | Not modeled. | adopt as a check (T1.5) |
| NAT on DRG: stateless 1:1, equal-length original and translated CIDRs (GA 2026-10-01) [O21][O22]. | Not modeled. | defer (T3.4) |
| VLAN CIDRs "must be within the VCN's CIDR and can't overlap with the CIDRs of the other subnets and VLANs in the VCN", and cannot be changed later [O33]. | Not modeled. | adapt (T2.16) |
| Service limits [O2]: 16 IPv4 CIDRs per VCN; 300 subnets per VCN; 16 IPv4 CIDRs per subnet; 16 IPv6 prefixes per VCN and per subnet; VCNs per region 50 (Universal Credits) or 10 (PAYG/trial); 10 LPGs per VCN; 300 VCN attachments per DRG. | Not checked. | adopt as soft warnings (T1.4) |
| A VCN IPv4 CIDR cannot be removed while an address in it is in use, and a VCN must keep at least one IPv4 CIDR [O8]. A subnet must keep at least one IPv4 CIDR [O13]. | Not checked. | adopt as what-if checks (T1.6) |

## 3. Prioritized recommendations

### Tier 1: high value, fits the current architecture, no PrefixRecord change

**T1.1 `cidrctl conflicts` / `validate` and an overlap summary per domain** (size S)
- **Value:** CI and pre-change gates; a scriptable answer to "is this inventory clean?".
- **OCI angle:** OCI does not block overlapping remote-peering designs [O16], so the check has to happen before the change.
- **Design:**
  - `cidr_core`: reuse `InventoryRules.conflicts()` and `validateInventory()` [R4].
  - `cidr_cli`: new subcommands with table/json output and exit code 3 on conflicts, matching the existing convention [R9][R1].
  - App: a count per domain in the Conflicts view, following UDDI's Overlapping IP Blocks monitor [U1].
- **Contract:** new CLI commands only.
- **Risks:** none against the premises.

**T1.2 Next-available parity: `--count`, `--exclude`, bulk carve** (size S-M)
- **Value:** plan a whole VCN subnet set in one step.
- **OCI angle:** 300 subnets per VCN [O2]. Covers both IPv4 and IPv6 /64 carving inside a VCN prefix [O1][O3].
- **Design:**
  - `cidr_core`: `available()` already returns a list [R4]. Add `exclude: List<Cidr>`, and give AddressPlanner an `N` that returns N non-overlapping candidates.
  - `cidr_cli`: `recommend --count N --exclude <cidr>...`.
  - `--apply` reserves all N children in one `InventoryStore.reserve` transaction (all or none), copying parent metadata as today.
  - Infoblox equivalents: WAPI `num`/`exclude` [N7], Terraform `subnet_count` [G5] and `exclude[]` [G16].
- **Contract:** `reserve` must accept a batch. That is a `cidr_data` API change, not a schema change.
- **Risks:** keep the existing transactional re-check; Infoblox's documented race is what to avoid [U7][N6].

**T1.3 Capacity metrics, computed the NIOS container way** (size S-M)
- **Value:** see how much of each regional pool is already carved, so you know where to expand.
- **OCI angle:** the most useful metric is VCN subnet coverage, i.e. how much of each VCN is carved into subnets.
- **Design:**
  - `cidr_core`: extend AddressSpaceSummary [R5] with:
    - blocked addresses per status (planned, reserved, active);
    - the count of free blocks, as a fragmentation measure;
    - coverage % for a pool or VCN.
  - App: show these in the planner rail.
  - `cidr_cli`: `cidrctl capacity [--routing-domain] [--over 80]`, with the threshold given as a flag.
  - Infoblox semantics: NIOS container utilization [N13] and the UDDI `allocation_v4` breakdown [G7].
- **Contract:** additive JSON fields on the planner output.
- **Risks:** label the figures as carved share, not host usage, so nobody reads them as DHCP-style utilization.

**T1.4 OCI policy hardening** (size S-M)
- **Value:** catch invalid plans before they reach Terraform.
- **OCI rules to encode:**
  - reject 169.254.0.0/16, 224.0.0.0/4 and 240.0.0.0/4 [O1];
  - VCN prefix length /16-/30 [O1], for `kind=vcn` only; allocation records stay free-form;
  - IPv6 subnets must be exactly /64 [O1][O3][O41];
  - IPv6 VCN prefixes: Oracle GUA /56 only, ULA and BYOIPv6 /64 or larger [O1][O3];
  - soft limits: 16 IPv4 CIDRs per VCN, 300 subnets per VCN, 16 IPv4 CIDRs per subnet, VCNs per region [O2];
  - optional domain-wide profile: hold 100.64.0.0/10 where Exadata X8M/X9M/X11M clients live [O34].
- **Design:**
  - `cidr_core`: AddressPolicy and InventoryRules.
  - `reserve` refuses hard violations: disallowed ranges, VCN size, IPv6 /64.
  - Imports keep the same violations as visible warnings (rule 6).
- **Contract:**
  - The IPv6 /64 size rule is consistent across Oracle pages and can be enforced.
  - The IPv6 assignable count is not: ipv6.htm says 8 reserved [O3], the VCN and subnet overview says 3 [O41]. Keep the current "unresolved" IPv6 capacity note [R2][R5] and do not publish an assignable-host figure.
  - Treat the limit values as configurable defaults (see the notes at the end of section 5).
- **Risks:** service limits vary by tenancy and can be raised [O2], so warn rather than block.

**T1.5 OKE CIDR checks** (size S)
- **Value:** a flannel cluster's Pods CIDR "cannot" be changed after creation [O27], so a collision has to be caught before it is created.
- **OCI rules to check:**
  - flannel: the VCN and its subnets must not overlap the pods or services CIDRs [O27];
  - VCN-native: the VCN and its subnets must not overlap the services CIDR [O27];
  - defaults: pods 10.244.0.0/16 and services 10.96.0.0/16; IPv6 fd00:eeee:eeee:0000::/96 and fd00:eeee:eeee:0001::/108 [O29];
  - flannel capacity: a /25 per node, so nodes = 2^(25 - pods prefix length); a /16 gives 512 nodes [O27];
  - VCN-native capacity [O30]:
    - each pod takes one pod-subnet IP, up to 256 per node;
    - max pods per node = MIN((VNICs - 1) x 31, 256);
    - size the pod subnet from node count x max pods per node, plus the 3 reserved addresses [O1];
  - the API endpoint subnet: "A /29 ... is usually sufficient" [O27].
- **Design:**
  - `cidr_cli`: `cidrctl oke-check --vcn <id> [--pods] [--services]`, which runs the existing domain conflict check against the VCN's records.
  - `cidr_core`: a sizing helper for both network types.
- **Contract:** none. Persisting cluster CIDRs as records is T2.7/T3.
- **Risks:** [O27] does not say whether flannel pods CIDRs may repeat across clusters (UNVERIFIED). Until it is confirmed, check each cluster against its own VCN and do not add pods CIDRs to the shared domain as blocking records.

**T1.6 What-if grow and shrink checks** (size M)
- **Value:** answers these questions:
  - "Can this subnet go from /25 to /24?"
  - "Which secondary CIDR can I add to this VCN?"
  - "Can I remove this VCN CIDR?"
- **OCI rules:**
  - a subnet CIDR edit must stay within one of the VCN's CIDRs, keep the same network address, and not drop in-use addresses [O13];
  - an added VCN CIDR "must not overlap with any other address range in the VCN or in a peered VCN" and must not include an address used in an existing route rule [O6];
  - the 16-CIDR cap applies [O2];
  - a VCN CIDR cannot be removed while an address in it is in use, and at least one IPv4 CIDR must remain [O8].
- **Design:**
  - `cidr_core`: three functions, all scoped to the routing domain:
    - `canGrow(record, newPrefix)`;
    - `secondaryVcnCandidates(vcn, prefix)`;
    - `canRemove(vcnCidr)`, which checks for child subnet records in the block.
  - App: a planner action. `cidr_cli`: `recommend --grow <id>`.
- **Contract:** additive.
- **Risks:** CIDR Atlas does not collect route rules or private IPs. Results must say "route rules and in-use addresses not checked" until T3.2/T3.6.

**T1.7 Reconciliation views and an "adopt into plan" step** (size S-M)
- **Value:** shows observed-but-unplanned networks and planned-but-never-observed reservations. This is the Infoblox unmanaged-data concept [N8][N28], and UDDI's IPAM vs DISCOVERED indicators [G2].
- **Design:**
  - App and CLI filters, derived from existing fields:
    - observed only: `source=oci` with no planning parent;
    - planned only: no `resourceId`, status planned or reserved;
    - retired locally but still live: an existing warning [R1].
  - "Adopt" sets `parentId` on an observed VCN to a planning allocation. `parentId` is a preserved planning field [R1], so this survives refresh.
- **Contract:** none.
- **Risks:** adopting still has to pass explicit-parent validation (rule 3).

**T1.8 IaC and view export** (size S-M)
- **Value:** hand approved CIDRs to Terraform or OCI Resource Manager without CIDR Atlas ever touching OCI. This is the counterpart to Infoblox's `next_available_id` Terraform pattern [G3][G16].
- **Design:**
  - `cidr_cli`: `export --format tfvars-json` for planned and reserved VCN and subnet records, shaped for `oci_core_vcn.cidr_blocks` [O4] and `oci_core_subnet` CIDR arguments [O9].
  - App: "Export current view", which honors the active filters, as UDDI does [U13].
- **Contract:** new export formats only.
- **Risks:** exports of real inventories can contain customer metadata, so keep fictional examples only (AGENTS.md).

**T1.9 External supernets as allocation records (documentation)** (size S)
- **Value:** recommendations avoid on-prem and other-cloud space today. This mirrors the purpose of UDDI federated blocks for on-prem and other clouds [U2].
- **OCI angle:** VCN CIDRs must not overlap "CIDRs in a connected on-premises network" or a peered VCN [O1].
- **Design:** user guide and fictional examples only: allocation records in the same routing domain.
- **Risks:** they look identical to OCI pools. T2.5 fixes that.

**T1.10 Small items** (size S)
- Equal-CIDR VCN/subnet regression test [N4][O13].
- Delete preview listing all descendants.
- `cidrctl retire <id>`. This is a status change with history; the CLI cannot delete or retire today [R9]. Prefer retire over adding a hard delete.

### Tier 2: valuable, needs model or schema work

Records are stored as JSON documents in a `prefixes` table with `PRAGMA user_version = 1` [R6]. A new record field is therefore a codec change plus a version bump, not a column migration. New tables (attribute definitions, templates, saved views, acknowledgements) do need DDL.

Suggested order: T2.5, T2.4, T2.3, T2.2, T2.13, then the rest. T2.1 comes last, because T2.3 and the existing fixed fields cover most needs.

**T2.1 Typed planning attributes** (size L)
- **Value:** cost centre, application, data classification and similar fields, without code changes.
- **Infoblox model:** NIOS EA types and flags [N10].
- **Design:**
  - `cidr_core`: an `AttributeDefinition` with these properties:
    - name and type (string, list, integer, date, email, url);
    - allowed values;
    - required and inheritable flags;
    - the kinds it applies to.
  - Each record gets `attributes: Map<String, Object>`.
  - Validation lives in `InventoryRules`, so GUI, CLI and CSV enforce the same rules. NIOS enforces required values in Grid Manager only [N10].
  - `cidr_data`: a definitions table; CSV columns named `attr:<name>`.
  - App: an editor plus definition management.
- **Contract:** CONTRACT.md record shape, CSV header and backup format version 2.
- **Risks:**
  - existing fixed fields stay, so no data migration is forced;
  - imports must still preview and apply atomically even when required values are missing, so record a warning on import instead of blocking (rule 6);
  - deleting a list value must not silently rewrite records. NIOS removes the value from every object that uses it [N10]; do not copy that.

**T2.2 Inheritance along the explicit chain** (size M)
- **Value:** set owner and environment once on an allocation and have them flow down.
- **Infoblox model:** NIOS states Inherited and Overridden [N11]; UDDI tags flow to children unless overridden [U1].
- **Design:** `cidr_core` resolves effective values at read time from the explicit parent or VCN identity chain. Each record stores only its overrides.
- **Contract:** additive. The effective value is computed and appears in exports as a separate column.
- **Risks:** never inherit through containment (rule 3). Read-time resolution avoids stale copies, which NIOS works around with descendant actions [N11].

**T2.3 OCI tag ingestion** (size M)
- **Value:** use the OCI defined tags people already maintain (Environment, CostCenter) for filters and policy.
- **OCI facts:**
  - `ListVcns` returns `[]Vcn` [O42].
  - The Vcn and Subnet models include `freeform_tags` and `defined_tags`, plus `system_tags` [O43][O44].
  - Terraform exposes the same maps [O4][O9].
  - Defined tags are namespaced [O32].
- **Design:**
  - `cidr_data` importer: read the tag maps from the raw objects the adapter already keeps [R8], so no new OCI calls are needed.
  - Confirm the CLI's JSON key spelling (`freeform-tags`/`defined-tags`) with a fictional fixture. The CLI reference page does not document the output shape [O45].
  - Store them as read-only `sourceTags`, refreshed on each import and kept separate from local attributes, as UDDI does [U11].
  - An optional user-defined mapping fills a planning field only when that field is empty (rule 5).
- **Contract:** record field and import normalization.
- **Risks:** tags may contain customer metadata; Oracle advises against confidential tag content [O32]. Keep them out of examples and test fixtures.

**T2.4 Prefix-length policy per pool** (size S-M)
- **Value:** standards such as "workload VCNs /20-/22, default /22" become enforced.
- **Infoblox model:** UDDI min/default/max [U10][G7].
- **Design:**
  - Store `childPrefixPolicy {min, default, max}` on allocation and VCN records.
  - The planner's default prefix comes from the policy.
  - `reserve` refuses out-of-policy children. Imported or manual records are flagged, which mirrors UDDI's flag-not-block for pre-existing and discovered objects [U10].
- **Contract:** record field.
- **Risks:** for VCN and subnet children, the policy must sit inside OCI's /16-/30 bounds [O1].

**T2.5 Block intent: held, external, earmarked** (size M)
- **Value:** separates three kinds of space:
  - "never allocate" space: on-prem, partner, OKE defaults, the Exadata interconnect;
  - space managed by another cloud or authority;
  - team earmarks.
- **Infoblox model:** Reserved Block [G13], Federated Block authority [U2], Forward-Looking Delegation [U9].
- **Design:**
  - A new `intent` field (allocatable, held, external, earmarked) plus an `authority` text field, rather than overloading status `reserved`.
  - Recommendations skip held and external space and only use earmarked space for its named owner.
  - Utilization reports these as separate categories, following UDDI `allocation_v4` [G7].
- **Contract:** record field; the planner filter changes.
- **Risks:** held and external records still take part in conflict checks (rule 6).

**T2.6 Acknowledged overlaps** (size M)
- **Value:** known, accepted overlaps stop cluttering the review list but stay visible. Example: LPG spokes that may overlap each other [O15].
- **Infoblox model:** UDDI Overlapping Block [G9]. AWS VPC IPAM has a similar "Ignored" overlap status [W3] (secondary vocabulary only).
- **Design:**
  - `cidr_data`: an acknowledgements table (record pair, reason, date).
  - Conflicts are reported in an acknowledged bucket.
  - An acknowledgement is invalidated automatically when either CIDR changes.
- **Contract:** new table and a new conflict-output field.
- **Risks:** never drop an acknowledged conflict from the output (rule 6). Separate routing domains remain the right answer for truly unconnected space (rule 2).

**T2.7 VCN and landing-zone templates** (size M-L)
- **Value:** one action produces a standard spoke VCN and its subnet set.
- **Infoblox model:** NIOS network templates, with a fixed netmask and nested range templates [N7][N5][N9].
- **OCI examples:**
  - OKE: API /29 [O27], pod subnet sized from nodes x max pods per node [O30], worker and LB subnets;
  - OCVS: recommended /21 split into 10 x /25 [O33];
  - Exadata: client/backup minimum sizes per rack shape [O34].
- **Design:**
  - Templates are stored as JSON, in a table with import/export. Each has a VCN size plus ordered child slots, each with a name pattern, kind, prefix or demand, and attributes.
  - `cidr_core` plans the layout against the inventory: pool, then VCN, then subnets.
  - The result is shown as a preview and applied with one batched `reserve` (T1.2).
- **Contract:** new template format.
- **Risks:** templates must not hard-code customer data; ship fictional templates only.

**T2.8 Persisted thresholds** (size S)
- **Infoblox model:** trigger/reset defaults of 95%/85% in NIOS [N14][N15]; a 90% default with ancestor roll-up in UDDI [U4][U16].
- **Design:** store `{trigger, reset}` per pool or domain; the planner and `cidrctl capacity` flag pools that cross the trigger.
- **Risks:** visual flags only. There is no background job (rule 9).

**T2.9 Audit history enrichment** (size M)
- **Infoblox model:** NIOS detailed audit with new values [N23]; UDDI audit with request ID, resource ID and CSV export [U14].
- **Design:**
  - `audit_entries` gains `source` (gui, cli, import, discover), record ids, a JSON before/after diff and an optional reason or ticket.
  - App: a per-record history panel.
  - CLI: `history --record <id> --format csv`.
- **Contract:** audit schema, `user_version` 2.
- **Risks:** this is still not a tamper-evident ledger. Say so in the docs.

**T2.10 Lifecycle dates and quarantine** (size S-M)
- **Design:**
  - `targetDate` and `expiresAt` on planned or reserved records. Expired reservations are flagged, never auto-freed.
  - `retiredAt` plus a configurable hold period before retired space is recommended again. Today planning and conflict checks skip retired records, so their space counts as free immediately [R5][R4].
  - An optional ticket field is the only part of NIOS approval workflows worth keeping locally [N24].
- **Risks:** none against the premises.

**T2.11 Routing domain as a managed object** (size M)
- **Design:** a `routing_domains` table holding name, description, owner, type (such as drg-mesh, on-prem, isolated or public) and connected-domain edges. Records keep the string key.
- **Why:** prerequisite for T3.1. It also covers the case-sensitivity decision already deferred as #45 [R12].
- **Risks:** connected edges are documentation until T3.1. Do not infer conflicts from them before that.

**T2.12 Saved views** (size S)
Named personal filters with grouping by attribute, from NIOS smart folders [N12].

**T2.13 "Not observed since" flag** (size M)
- Persist import coverage (region and compartment pairs, `collectedAt`) as structured history, not text.
- A record from a covered scope whose `verifiedAt` predates the latest covering import becomes a retirement candidate. It is retired only by an explicit human action.
- This contrasts with UAI's automatic soft/hard delete [U1], which rule 5 forbids.

**T2.14 CSV import modes** (size S-M)
- Modes: insert-only, merge-empty-only, override, retire. Adapted from NIOS Add/Merge/Override/Delete [N21][N22].
- Always previewed and atomic.

**T2.15 OCI IPv6 prefix sources** (size S)
- OCI sources [O1][O3][O31]:
  - Oracle GUA /56, assigned by Oracle and not plannable;
  - ULA /64 or larger, with the fd00 half recommended;
  - BYOIPv6, imported as /48 or larger and assigned to VCNs as /64 or larger.
- Store a `prefixSource` field and warn above the configurable per-VCN and per-subnet prefix counts (see the notes in section 5).

**T2.16 VLAN kind (manual)** (size S)
- A new `vlan` PrefixKind: contained in the VCN, must not overlap subnets or other VLANs, and immutable once created [O33].
- Without it, free-space views can recommend space that OCVS VLANs already use.
- Discovering VLANs needs a new OCI call (Tier 3). Relevant only to OCVS estates.

**T2.17 Capacity history and runway** (size M)
- **Value:** answers "at the current carve rate, this regional pool is full in N months". Infoblox's Address Space Perspective advertises utilization trends and fragmentation [U1] (release-note excerpt).
- **Design:** on each apply (reserve, import, discover), store a T1.3 capacity snapshot per pool in a local table; chart and export it. No background sampling (rule 9).
- **Risks:** trends are only as complete as import coverage. Label them conditional, as availability already is [R1].

### Tier 3: depends on the team service or broader OCI collection

**T3.1 Topology-aware overlap across DRG and LPG** (size L)
- **OCI rules:**
  - peers of one VCN over remote peering must not overlap each other, and OCI does not enforce this [O16];
  - an LPG hub's spokes may overlap each other [O15];
  - a VCN attaches to "one and only one DRG" [O19].
- **Design:**
  - `cidr_oci`: new read-only list calls for DRG attachments and LPGs.
  - `cidr_core`: peering-edge constraints evaluated over domain edges (T2.11).
- **Premise conflict:** CONTRACT.md places connectivity outside the current milestone [R1].

**T3.2 Route-rule-aware VCN CIDR additions** [O6] (size M)
Needs route-table collection.

**T3.3 DRG route conflict evidence** (size M)
Import DRG route tables and surface routes in "conflict" status [O19]. These mark identical CIDRs learned from several attachments. They are evidence of duplicate address space, not of partial overlap.

**T3.4 NAT on DRG mappings** (size M-L)
- Original-to-translated pairs of equal prefix length across domains [O22], allocated from a translated pool.
- The feature went GA 2026-10-01 [O21]. No limits or IPv6 support are documented [O22]. Wait for the documentation to settle.

**T3.5 Other observed CIDR carriers** (size M)
- Sources: IPSec static routes and encryption domains [O23], LPG `peerAdvertisedCidr` [O15], Network Firewall address lists [O35].
- Allocating transit link nets from a dedicated pool can be done manually today: IPSec BGP /30-/31 [O24] and FastConnect /28-/31 [O25].

**T3.6 Private IP and utilization inventory (DDI-adjacent)** (size M-L)
- Opt-in offline import of JSON from `oci network ipam list-ip-inventory`, `get-subnet-cidr-utilization` and `get-vcn-overlap` [O40], as a cross-check and for subnet utilization. This needs `read ipam` [O37].
- VNIC private IP CIDR objects [O12] would be the most detailed level of inventory.
- This is the boundary with host-level IPAM. Keep it read-only and opt-in.

**T3.7 Approval workflow and RBAC** (size L)
- Infoblox models:
  - NIOS approval workflows [N24];
  - UDDI Access Views [U15][U1]: permissions attach to blocks and are inherited by children, and next-available is limited to the parent CIDR of the access view.
- These are design inputs for the future team service (rule 7). Do not build them into the local app.

**T3.8 Central allocation authority** (size L)
A service-side transactional next-available removes the documented concurrent-candidate race [U7][N6]. Desktop collectors stay read-only [R2].

## 4. Do not adopt

1. **Hierarchy inferred from containment** (NIOS auto-creates containers [N3]). Violates rule 3.
2. **Cascade-delete as the API default** (WAPI `remove_subnets` deletes children by default [N7]). Default to refusing.
3. **Required fields enforced in the GUI only** (WAPI and CSV can skip them [N10]). Enforce in `cidr_core`.
4. **Non-atomic CSV import with stop/skip and no rollback** [N21][N20]. Violates rule 6.
5. **Next-available without a transactional re-check** (the documented race [U7][N6]).
6. **Automatic soft/hard deletion of stale discovered objects** [U1]. Violates rule 5.
7. **Random pick among duplicate discovered CIDRs** (AWS auto-import [W2], secondary reference). Keep both and flag them.
8. **DNS-view coupling to network views** [N1]. DDI-only.
9. **DHCP/lease-weighted utilization** [U4][N13]. CIDR Atlas has no lease data; use carved-share metrics.
10. **Host-level IP Map, conflict resolution on MAC or lease** [N8]. Out of scope for prefix planning.
11. **Active network discovery or probing** [N29]. Violates rule 9.
12. **Background or scheduled collection and scheduled execution** [N25]. Violates rule 9; CIDR Atlas never provisions OCI.
13. **Cloud write-back of reservations** (GCP internal ranges [U2], AWS VPC IPAM scope authority [W4]). No OCI equivalent was found; use IaC export.
14. **RIR registration** [N7]. Not relevant to private OCI planning.
15. **Asset-insight security/FinOps findings** (orphaned LBs, idle VMs [U1]). Not CIDR planning.
16. **Sync through a shared SQLite file** as a substitute for multi-user features. Violates rule 7.

## 5. Sources

**Infoblox NIOS (docs.infoblox.com)**
- [N1] https://docs.infoblox.com/space/nios90/280763374
- [N2] https://docs.infoblox.com/space/nios90/1468335066
- [N3] https://docs.infoblox.com/space/nios90/1346013877
- [N4] https://docs.infoblox.com/space/nios91x/2396391590
- [N5] https://docs.infoblox.com/space/nios90/1346011199/Add+Networks
- [N6] https://docs.infoblox.com/space/nios86/1104970165/Configuring+the+Next+Available+Network+or+IP+Address
- [N7] https://docs.infoblox.com/download/attachments/15433773/Infoblox%20NIOS%20WAPI%209.x%20Reference%20Guide.pdf (WAPI 2.13.6)
- [N8] https://docs.infoblox.com/space/nios90/1344964627
- [N9] https://docs.infoblox.com/space/nios90/1393558852/About+IPv4+Range+Templates
- [N10] https://docs.infoblox.com/space/nios86/946439187
- [N11] https://docs.infoblox.com/space/nios90/1340541030
- [N12] https://docs.infoblox.com/space/nios90/280857674
- [N13] https://docs.infoblox.com/space/nios90/1345162224
- [N14] https://docs.infoblox.com/space/nios90/1406435401
- [N15] https://docs.infoblox.com/space/nios85/35752795
- [N16] https://docs.infoblox.com/space/nios90/1345063445/Splitting+IPv4+Networks+into+Subnets
- [N17] https://docs.infoblox.com/space/nios90/1345162266/Joining+IPv4+Networks
- [N18] https://docs.infoblox.com/space/nios86/1103691780
- [N19] https://docs.infoblox.com/space/nios90/1467023597/Emptying+the+Recycle+Bin
- [N20] https://docs.infoblox.com/space/nios90/422248651/Limitations+of+CSV+Import+and+Export
- [N21] https://docs.infoblox.com/display/nios86/Importing+and+Exporting+Data+using++CSV+Import
- [N22] https://docs.infoblox.com/space/nios90/280791008/Importing+Multiple+Action+CSV+file
- [N23] https://docs.infoblox.com/space/nios90/1393852570
- [N24] https://docs.infoblox.com/display/nios85/Configuring+Approval+Workflows
- [N25] https://docs.infoblox.com/space/nios90/1454964989/Scheduling+Additions+and+Modifications
- [N26] https://docs.infoblox.com/space/nios90/1343324540/Defining+Global+Permissions
- [N27] https://docs.infoblox.com/space/nios90/1468466176/Defining+Policies+for+Handling+Discovered+Data
- [N28] https://docs.infoblox.com/space/nios90/1432719297
- [N29] https://infoblox-docs.atlassian.net/wiki/pages/viewpage.action?pageId=1142292482 (NIOS 9.0.x vDiscovery jobs)
- [N31] https://docs.infoblox.com/space/nios90/1432715867

**Infoblox Universal DDI and Universal Asset Insights**
- [U1] https://docs.infoblox.com/space/BloxOneDDI/186713611/What%E2%80%99s+New+in+Infoblox+Universal+DDI
- [U2] https://docs.infoblox.com/space/BloxOneDDI/846922305/GCP+Internal+Range+Integration
- [U3] https://docs.infoblox.com/space/BloxOneDDI/731185389
- [U4] https://docs.infoblox.com/space/BloxOneDDI/186746138/Configuring+Address+Spaces
- [U5] https://docs.infoblox.com/space/BloxOneDDI/186877118
- [U7] https://docs.infoblox.com/space/BloxOneDDI/186617449/Configuring+Next+Available+Network
- [U9] https://docs.infoblox.com/space/BloxOneDDI/2449047663/Creating+Forward-Looking+Delegations+in+the+Network+View
- [U10] https://docs.infoblox.com/space/BloxOneDDI/2448916588/Configuring+a+Prefix+Length+Policy+on+an+Address+Block
- [U11] https://docs.infoblox.com/space/BloxOneDDI/2448982115/Tagging+Cloud-Discovered+Objects
- [U12] https://infoblox-docs.atlassian.net/wiki/spaces/BloxOneDDI/pages/684622525/Managing+Public+Cloud+Providers
- [U13] https://docs.infoblox.com/space/BloxOneDDI/2448883733/Exporting+IPAM+Data+to+CSV
- [U14] https://docs.infoblox.com/space/BloxOneCloud/35430270/Viewing+Audit+Logs
- [U15] https://docs.infoblox.com/space/BloxOneCloud/680657470/Supported+Objects+for+Access+Views
- [U16] https://docs.infoblox.com/space/BloxOneDDI/186876614
- [A1] https://docs.infoblox.com/space/UniversalAssetInsights/2236284934/Oracle+Cloud+Infrastructure
- [A2] https://docs.infoblox.com/space/UniversalAssetInsights/1501397385/Viewing+Discovered+IPAM+Resources
- [A3] https://docs.infoblox.com/space/UniversalAssetInsights/2396491547/Improved+Naming+for+Discovered+IP+Spaces+in+IPAM
- [A4] https://docs.infoblox.com/space/UniversalAssetInsights/1614381557/Discovered+Asset+Types+and+Attributes+by+Discovery+Provider

**Infoblox GitHub and Terraform docs**
- [G1] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/resources/ipam_ip_space.md
- [G2] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/resources/ipam_address_block.md
- [G3] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/resources/ipam_subnet.md
- [G5] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/data-sources/ipam_next_available_subnets.md
- [G6] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/data-sources/ipam_next_available_address_blocks.md
- [G7] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/resources/federation_federated_block.md
- [G8] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/resources/federation_federated_realm.md
- [G9] https://raw.githubusercontent.com/infobloxopen/terraform-provider-bloxone/main/docs/resources/federation_overlapping_block.md
- [G10] https://github.com/infobloxopen/terraform-provider-bloxone/blob/main/docs/resources/cloud_discovery_provider.md
- [G11] https://github.com/infobloxopen/bloxone-go-client/blob/main/ipam/docs/AddressBlockAPI.md
- [G12] https://github.com/infobloxopen/bloxone-go-client/blob/main/ipam/docs/SubnetAPI.md
- [G13] https://github.com/infobloxopen/bloxone-go-client/blob/main/ipamfederation/docs/ReservedBlock.md
- [G14] https://github.com/infobloxopen/bloxone-go-client/blob/main/ipamfederation/docs/NextAvailableFederatedBlockAPI.md
- [G16] https://github.com/infobloxopen/terraform-provider-infoblox/blob/main/docs/resources/network.md (v3.0.0-beta)
- [G17] https://github.com/infobloxopen/terraform-provider-infoblox/blob/v2.13.0/docs/resources/infoblox_ipv4_network.md

**Oracle Cloud Infrastructure (docs.oracle.com)**

[O42] is the exception: it is Oracle's official oci-go-sdk repository on GitHub, used because the docs.oracle.com API reference page is JS-gated.

- [O1] https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/overview.htm
- [O2] https://docs.oracle.com/en-us/iaas/Content/General/Concepts/servicelimits.htm
- [O3] https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ipv6.htm
- [O4] https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_vcn.html
- [O5] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/create_vcn.htm
- [O6] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/add_cidr_to_vcn.htm
- [O8] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/remove_cidr_block_vcn.htm
- [O9] https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/core_subnet.html
- [O10] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/create_subnet.htm
- [O12] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingIPaddresses.htm
- [O13] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/edit_subnet.htm
- [O14] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/add-subnet-prefix.htm
- [O15] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/localVCNpeering.htm
- [O16] https://docs.oracle.com/iaas/Content/Network/Tasks/scenario_e.htm
- [O19] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingDRGs.htm
- [O21] https://docs.oracle.com/en-us/iaas/releasenotes/network/nat-drg.htm
- [O22] https://docs.oracle.com/iaas/Content/Network/Tasks/nat-drg-overview.htm
- [O23] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/overviewIPsec.htm
- [O24] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/ip-sec-con-create.htm
- [O25] https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/fastconnectrequirements.htm
- [O27] https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengcidrblocks.htm
- [O29] https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/containerengine_cluster.html
- [O30] https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpodnetworking_topic-OCI_CNI_plugin.htm
- [O31] https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/BYOIP.htm
- [O32] https://docs.oracle.com/en-us/iaas/Content/Tagging/Concepts/taggingoverview.htm
- [O33] https://docs.oracle.com/en-us/iaas/Content/VMware/Tasks/vlan-create.htm
- [O34] https://docs.oracle.com/en/engineered-systems/exadata-cloud-service/ecscm/ecs-network-setup.html
- [O35] https://docs.oracle.com/en-us/iaas/Content/network-firewall/address-list-create.htm
- [O37] https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/ip_inventory.htm
- [O40] https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/ipam.html
- [O41] https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/Overview_of_VCNs_and_Subnets.htm
- [O42] https://raw.githubusercontent.com/oracle/oci-go-sdk/master/core/list_vcns_request_response.go
- [O43] https://docs.oracle.com/en-us/iaas/tools/python/latest/api/core/models/oci.core.models.Vcn.html
- [O44] https://docs.oracle.com/en-us/iaas/tools/python/latest/api/core/models/oci.core.models.Subnet.html
- [O45] https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html

**AWS (secondary vocabulary reference only, not an authority for Infoblox or OCI claims)**
- [W2] https://docs.aws.amazon.com/vpc/latest/ipam/create-top-ipam.html
- [W3] https://docs.aws.amazon.com/vpc/latest/ipam/monitor-cidr-compliance-ipam.html
- [W4] https://docs.aws.amazon.com/vpc/latest/ipam/integrate-infoblox-ipam.html

**CIDR Atlas repository (repository paths, working tree as of 2026-10-16)**
- [R1] docs/CONTRACT.md
- [R2] docs/architecture.md
- [R3] packages/cidr_core/lib/src/prefix_record.dart
- [R4] packages/cidr_core/lib/src/inventory_rules.dart, packages/cidr_core/lib/src/inventory_index.dart
- [R5] packages/cidr_core/lib/src/planning_space.dart, packages/cidr_core/lib/src/address_planner.dart
- [R6] packages/cidr_data/lib/src/store.dart
- [R7] packages/cidr_data/lib/src/import.dart
- [R8] packages/cidr_oci/lib/src/client.dart. Discovery calls `network vcn|subnet list --all` with no field projection and keeps each full resource object (`{...resource, 'region': region}`). There are no tag references in the adapter or the importer.
- [R9] packages/cidr_cli/lib/cidr_cli.dart, packages/cidr_cli/lib/src/recommendation.dart
- [R10] apps/cidr_atlas/lib/visual_planner.dart
- [R11] AGENTS.md
- [R12] PROJECT.md, docs/plans/2026-10-16-review-remediation.md
- [R13] apps/cidr_atlas/lib/app.dart, apps/cidr_atlas/lib/controller.dart

**Notes on conflicting or unverified sources**
- **VCN IPv4 CIDR count.**
  - create_vcn.htm's Console field says "Specify up to five but at least one" and adds "You can add or remove CIDR blocks later" [O5].
  - Service limits and ipv6.htm say 16 per VCN [O2][O3].
  - These read as a create-time Console limit versus the total limit, not a true conflict. This assessment uses 16 as the configurable default.
- **IPv6 prefixes per VCN and per subnet.**
  - BYOIP.htm: "up to five total IPv6 prefixes per VCN and up to three per subnet" [O31].
  - Service limits: 16 per VCN and 16 per subnet [O2].
  - ipv6.htm says both "The subnet can only have one IPv6 prefix" and "A subnet can have more than one IPv6 prefix" [O3].

  This assessment uses the service-limit values as configurable warnings and does not hard-code them.
- **IPv6 reserved addresses.**
  - ipv6.htm: 8 reserved per /64, the first 4 and the last 4 [O3].
  - Overview of VCNs and Subnets: the first two and the last address are reserved "With IPv4 addresses and IPv6 addresses" [O41].
  - Unresolved. CIDR Atlas correctly shows no OCI IPv6 assignable count [R2].
- **IPv4 subnet size range.** No docs.oracle.com page read states an IPv4 subnet range separate from the VCN's /16-/30 [O1][O41]. The /16-/30 rule for subnets in CIDR Atlas is inferred from containment.
- **Same-CIDR VCN and subnet in OCI.** Inferred from [O13] ("within one of the VCN's CIDR block ranges"), not stated explicitly.
- **Infoblox OCI-to-IPAM object mapping.** UNVERIFIED. [A1] documents an IPAM Discovery toggle for OCI but no mapping. Only the AWS mapping is documented [A2].
- **OCI tags in `list` output.**
  - Supported at the API-model level: `ListVcns` returns `[]Vcn` [O42], and Vcn and Subnet carry `freeform_tags` and `defined_tags` [O43][O44].
  - The CLI's JSON key spelling is not documented on the command page [O45]. Confirm it with a fictional fixture before building T2.3.
- **OKE flannel pods CIDR reuse across clusters, and a "/19 typical" VCN-native pod subnet.** Neither is stated on [O27] or [O30]. Both were removed; T1.5 uses the documented per-node formulas instead.
- **Dropped as unverified or out of policy.** None of these are used above:
  - NIOS object-permission inheritance;
  - the NIOS capacity dashboards;
  - the resize orphan rule;
  - Infoblox-side AWS VPC IPAM behavior (vendor blog only).
- **Infoblox version baseline.**
  - NIOS 9.0.x, with NIOS 8.5/8.6 pages where cited and NIOS 9.1.x only for [N4]; WAPI 2.13.6 [N7].
  - Universal DDI release-note quotes are excerpts.
  - The Network View page needs a login, so Forward-Looking Delegations and Federated Pools are cited from release notes and the FLD page only [U1][U9].

## Verification status

Spot-checked against the cited pages on 2026-10-16: [O1], [O2], [O3], [O5], [O6], [O8], [O13], [O15], [O16], [O19], [O27], [O29], [O31], [O33], [O34], [O40], [O42]-[O44], [U3], [U5], [U7], [U10], [U11], [A1], [N3], [N6], [N10], [N13], [N14], [N15], [G7]-[G9].

Not verified:

- How Infoblox maps OCI VCNs and subnets into Universal IPAM objects.
- OCI CLI JSON key names for tags. Only the API models were checked.
- Whether flannel pods CIDRs can repeat across OKE clusters.

Not re-opened after the first research pass: [U1] release-note dates and quotes, [U4], [U9], [U13]-[U16], [N4], [N5], [N7], [N9], [N11], [N12], [N16]-[N29], [O10], [O12], [O14], [O21]-[O25], [O32], [O35], [O37], [A2]-[A4], [W2]-[W4].

Oracle documents IPv6 subnet reservations inconsistently: [O3] gives 8 addresses, [O41] gives 3. CIDR Atlas continues to omit an IPv6 assignable-host figure.
