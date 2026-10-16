# CIDR Atlas — guidance and examples

Author: Sergio Farfan <sergio.farfan@gmail.com>

## When do I enter a prefix?

A prefix is a network range written as a CIDR, such as `10.64.0.0/24`. The
network address identifies its beginning; `/24` identifies its size. More prefix
bits make a smaller block: IPv4 `/24` contains 256 total addresses, `/25` contains
128, and `/26` contains 64. Provider assignable capacity is a separate count.

| Task | Screen | Input |
| --- | --- | --- |
| Discover existing OCI networks | Import → Discover from OCI CLI | Profile, region, compartment and routing domain. OCI supplies CIDRs automatically. |
| Import an offline inventory | Import → Choose CSV or JSON | A populated supported inventory file. No separate network CIDR entry. |
| Register a range manually | New prefix | Full network CIDR, name, routing domain and any explicit parent. |
| Check a proposed range | Check CIDR | Full CIDR and routing domain; this check does not save it. |
| Find a new range | Planner | A pool boundary, then a child prefix length such as `24`, or address demand. |

Use **Help and examples** in the workspace header, **Import help**, **Discovery
help**, or **Planner help** for the relevant offline guide. Examples and reference
URLs can be selected and copied. Closing help retains the parent form or preview.

## Discover existing OCI CIDRs

1. Open **Import → Discover from OCI CLI** and choose an existing local profile.
2. Confirm the authentication mode: API key or security token. Repair credentials
   or renew an expired session through the OCI CLI outside CIDR Atlas.
3. Select **Load scopes**, then a READY region and the compartment containing the
   intended resources. **Enter scope manually** supports a region and compartment
   OCID when enumeration is unavailable; normal resource permissions still apply.
4. Enter a routing-domain name and select **Discover inventory**.
5. Review the network CIDR count, validation, conflicts, coverage and observation
   details. **Apply import** saves a nonempty valid batch locally, atomically.

Each run reads all VCN/subnet pages directly in one selected compartment and
region. Selecting tenancy root or a parent does not traverse its children.
Discover intended child compartments separately. Referenced VCN context does not
collect that VCN's other subnets. These scopes follow Oracle's
[VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html)
and [subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html)
contracts. Profiles follow Oracle's
[configuration format](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm)
and [session-token lifecycle](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm).

## What does an empty result mean?

**Discovery completed — no networks found** means the selected scope returned no
VCN/subnet CIDRs. No manual CIDR is needed, and Apply is disabled because there
is nothing to save. Check the profile/tenancy, actual resource region, and direct
compartment. Use **Choose another compartment or region** to discover again.
Tenancy root can be empty while child compartments contain networks.

An empty observation does not establish that the tenancy is empty or a previously
recorded range is free. Existing inventory remains present. Actual collection
failures and malformed/structural input remain errors. Coverage and observation
details are available in an expandable disclosure; read them before applying.

An empty CSV/JSON file requires a populated inventory file, rather than a CIDR
typed into the Import screen. Missing fields, malformed JSON, host bits and invalid
hierarchy must be corrected in the file before Apply becomes available.

## Offline inventory example

This minimal CSV is fictional and can be previewed without OCI access:

```csv
id,cidr,name,routingDomain,kind,status
example-pool,10.64.0.0/16,Fictional allocation,fictional-isolated,allocation,reserved
```

Use the documented column names shown above. `cidr`, `name` and `routingDomain` are required. A
network CIDR must have zero host bits: `10.64.1.0/24` is canonical;
`10.64.1.3/24` is rejected. Export a JSON backup to obtain a complete portable
template. CSV and Atlas backups retain their own routing domains; OCI JSON needs
the domain selected in Import. Imports retain omitted resources and OCI refresh
retains planning metadata such as ownership, status, hierarchy and notes.

## Choose the next range

Choose the routing domain, then an existing allocation/VCN pool or a manual
boundary. For example, `10.64.0.0/16` is the pool to search. Selecting an existing
VCN enables subnet planning under its declared relationship.

In **Choose by prefix**, enter only the requested child size, such as `24`.
A `/16` contains 256 aligned `/24` slots before inventory blockers. The full
candidate network address is calculated for you.

In **Size from address demand**, select Subnet and OCI IPv4 subnet policy, then
enter current or already planned peak IP demand, an explicit growth percentage,
and separate additional demand. For example:

```text
100 IPs × 1.20 growth + 4 additional IPs = 124 required assignable IPs
OCI /26: 64 total − 3 reserved = 61 assignable; too small
OCI /25: 128 total − 3 reserved = 125 assignable; 1 spare after allowances
```

Choose zero growth explicitly when the input already includes all intended growth.
Avoid counting the same service, maintenance or HA/DR demand twice. CIDR Atlas's
OCI IPv4 subnet policy supports `/16` through `/30`; Oracle describes the three
reserved IPv4 addresses in its
[Networking Overview](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/overview.htm).
IPv6 arithmetic remains exact without claiming a definitive OCI assignable count.

Free IP totals and free aligned slots answer different questions. A `/25` occupying
part of a `/24` leaves 128 raw free addresses but no complete free `/24` slot.
The planner reports exact counts while showing at most 12 ranked alternatives.
The inspector's child-slot count is theoretical and labeled **before blockers**.

Review a candidate, choose **Reserve selected CIDR**, and review its record before
saving. The store rechecks current conflicts and identity in the write transaction.
The saved rationale explains sizing and placement. A local reservation does not
provision OCI resources. Recalculate after changing inputs or inventory.

## Routing domain and coverage

A routing domain is a local overlap-check scope. Use one consistent name, such as
`corporate-connected`, for connected OCI, on-premises and other-cloud ranges that
must coexist. Independent isolated networks can use different domains and reuse
the same addresses. Tenancy or region alone does not define that boundary.

Declare allocation → VCN → subnet parents explicitly. Numeric containment alone
does not authorize a relationship. The displayed hierarchy shows address ancestry
and OCI membership; routing and security configuration determine connectivity.
Recommendations are available within the supplied inventory/domain and its known
coverage. Include unimported connected ranges before relying on a recommendation.

## CLI examples

Use an isolated database for fictional examples. These commands preview results:

```bash
cidrctl --db /tmp/cidr-atlas-example.sqlite import csv --file examples/fictional_inventory.csv
cidrctl --db /tmp/cidr-atlas-example.sqlite recommend --pool 10.90.0.0/20 --routing-domain fictional-connected --prefix 24
cidrctl --db /tmp/cidr-atlas-example.sqlite recommend --pool 10.90.0.0/20 --routing-domain fictional-connected --addresses 100 --growth-percent 20 --additional 4 --policy oci_ipv4 --kind subnet
```

Add `--parent ID` for an existing pool. Apply import with `--apply`, or reserve a
recommendation with `--apply --name NAME`, after reviewing the intended inputs.
Opening a database path may create the file; previews write no inventory/history
records. `cidrctl --help` and each command's `--help` include workflow guidance.
Keep exported backups protected and transfer JSON files rather than synchronizing
a live SQLite database through shared folders.
