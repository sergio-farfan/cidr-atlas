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
3. Select **Load scopes**. Keep one READY region, add other READY regions, or
   choose **All READY subscribed regions**. Select one direct compartment, or
   choose **All accessible compartments and subcompartments** to include tenancy
   root and every accessible active descendant in each chosen region.
   Compartments are shown by path, such as `root / prod / network`, so
   same-named compartments can be told apart; the selected OCID appears below
   the selector. When the direct compartment is the tenancy root (the default
   after **Load scopes**, or the tenancy OCID typed manually), a hint notes that
   root usually holds no networks; enable all accessible compartments to include
   its children.
4. Enter a routing-domain name and select **Discover inventory**.
5. Review the combined network CIDR count, validation, conflicts, coverage and
   observation details. **Apply import** saves a nonempty valid batch locally,
   atomically. Each network retains its actual region and compartment.

For example, two selected regions with all accessible compartments collect both
regions in one preview. All READY regions with all compartments build the broadest
available observation for that profile. A single selected compartment still means
its directly contained resources; select the all-compartments option to include
descendants. No manual network CIDR is needed for discovery.

**Enter scope manually** accepts comma-separated region names and a compartment
OCID when selectors cannot be loaded. Use full region identifiers such as
`us-ashburn-1`; three-letter keys such as `IAD` are resolved through the
tenancy's region subscriptions, and other forms are rejected. **Load scopes**
keeps typed entries in manual mode. Broad modes require successful live scope
enumeration; manual entry does not bypass IAM. All-region mode needs the profile's
default region to list subscriptions. Non-READY subscriptions are excluded and
reported. If a required list fails, the run stops with its failing scope and no
partial import can be applied. Use a narrower scope or correct permissions before
retrying. Cancellation leaves local inventory unchanged.

While profiles are read, scopes load or discovery runs, a progress panel appears
centred over the dialog, whatever the scroll position, and the form behind it is
locked. It shows the step (**Reading OCI profiles**, **Loading OCI scopes** or
**Discovering OCI inventory**), a progress bar that fills once the region and
compartment scope count is known (for example `2 of 6 region/compartment
scopes`), the current step, announced to screen readers, the elapsed time
(`Elapsed 01:05`) and, for discovery, the collection limit in effect. The panel's
**Cancel** stops the running request and returns to the form with a notice; the
dialog's own **Cancel** closes discovery and discards any result. Errors that
follow, such as a reached time limit, are scrolled into view.

Collection stops after 3 minutes for one region and compartment, or 30 minutes
for broader scopes. For a large tenancy, enter whole minutes from 1 to 1440 in
**Collection time limit, minutes (optional)**; leave it blank for the default.
A collection that reaches its limit returns nothing to apply.

The profile list comes from the configuration file you select, otherwise from
`OCI_CLI_CONFIG_FILE` when that variable is visible to the app, otherwise from
`~/.oci/config`. An app opened from Finder usually does not see variables
exported in a terminal, so select the file explicitly when you use a
non-default configuration.

Compartment enumeration uses Oracle's tenancy-root subtree request with
`ACCESSIBLE` and `ACTIVE`. INSPECT visibility is insufficient to guarantee network
read permissions, and IAM-hidden compartments remain unknown. Each selected
region/compartment pair fetches all VCN/subnet pages. Referenced VCN context does
not collect that VCN's other subnets. These semantics follow Oracle's
[compartment list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/compartment/list.html),
[region subscriptions](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/iam/region-subscription/list.html),
[VCN list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/vcn/list.html)
and [subnet list](https://docs.oracle.com/en-us/iaas/tools/oci-cli/latest/oci_cli_docs/cmdref/network/subnet/list.html).
Profiles follow Oracle's [configuration format](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdkconfig.htm)
and [session-token lifecycle](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/clitoken.htm).

## What does an empty result mean?

**Discovery completed — no networks found** means the selected scope returned no
VCN/subnet CIDRs. No manual CIDR is needed, and Apply is disabled because there
is nothing to save. Review the profile/tenancy, selected regions, compartment mode and IAM permissions.
In single-compartment mode, tenancy root can be empty while child compartments
contain networks. After a single-compartment discovery, **Retry with all
accessible compartments** starts discovery again at once with the same profile,
authentication, paths, time limit, regions and routing domain, including
subcompartments. If that profile is no longer in the configuration, nothing
starts and the dialog asks you to select a profile. **Review discovery scope**
opens a fresh discovery dialog. All-compartment mode
already includes accessible children; it does not establish visibility of hidden
resources.

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

A row whose `id` matches an existing record updates only the columns in the
file; columns you leave out keep their current values. A column that is present
but blank clears that field. `verifiedAt` should carry `Z` or a UTC offset,
such as `2026-10-15T18:30:00Z`; a zone-less value, as v0.3.0 exported, is read
as local time and the preview says how many values were read that way. Exported CSV marks cells that a spreadsheet would treat
as formulas with a leading `'`, which import removes again; a literal leading
`'` before `=`, `+`, `-` or `@` in a hand-written file is removed too. When
saving raw OCI CLI list output, use the CLI's `--all` option; a truncated page
produces a warning because unlisted ranges would look free.

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
If saving fails, the message appears in the open editor and your input is kept.
The saved rationale explains sizing and placement. A local reservation does not
provision OCI resources. Recalculate after changing inputs or inventory;
refreshing the inventory, including **Export all**, clears current results.

## Routing domain and coverage

A routing domain is a local overlap-check scope. Use one consistent name, such as
`corporate-connected`, for connected OCI, on-premises and other-cloud ranges that
must coexist. Independent isolated networks can use different domains and reuse
the same addresses. Tenancy or region alone does not define that boundary.

Declare allocation → VCN → subnet parents explicitly. Numeric containment alone
does not authorize a relationship. The planner uses compact controls beside its main address map, with details for
the selected network. The displayed address hierarchy shows ancestry and OCI
membership. Routes, gateways, DRGs, peering and security configuration determine
actual connectivity; those resources are not yet collected. A future connectivity
view will complement address planning without treating CIDR containment as a route.
Recommendations are available within the supplied inventory/domain and its known
coverage. Include unimported connected ranges before relying on a recommendation.

## CLI examples

Use an isolated database in a private directory for fictional examples. These
commands preview results:

```bash
mkdir -p ~/tmp
cidrctl --db ~/tmp/cidr-atlas-example.sqlite import csv --file examples/fictional_inventory.csv
cidrctl --db ~/tmp/cidr-atlas-example.sqlite discover oci --profile EXAMPLE --region us-phoenix-1,us-ashburn-1 --all-compartments --routing-domain fictional-connected
cidrctl --db ~/tmp/cidr-atlas-example.sqlite discover oci --profile EXAMPLE --all-regions --all-compartments --routing-domain fictional-connected
cidrctl --db ~/tmp/cidr-atlas-example.sqlite recommend --pool 10.90.0.0/20 --routing-domain fictional-connected --prefix 24
cidrctl --db ~/tmp/cidr-atlas-example.sqlite recommend --pool 10.90.0.0/20 --routing-domain fictional-connected --addresses 100 --growth-percent 20 --additional 4 --policy oci_ipv4 --kind subnet
cidrctl --db ~/tmp/cidr-atlas-example.sqlite export --file ~/tmp/cidr-atlas-example-backup.json
cidrctl --db ~/tmp/cidr-atlas-example.sqlite clear --routing-domain fictional-connected --yes
```

For discovery, use repeated/comma-separated `--region` or `--all-regions`, and
`--compartment-id` or `--all-compartments`. Each pair is mutually exclusive.
Explicit region names permit manual scope entry; all-region mode freshly resolves
READY subscriptions.

Add `--parent ID` for an existing pool. Apply import with `--apply`, or reserve a
recommendation with `--apply --name NAME`, after reviewing the intended inputs.
Opening a database path may create the file, with a warning on stderr; previews
write no inventory/history records. A discovery that finds no networks exits 0
and creates no database. A routing domain with no existing records prints a
warning naming known domains and near matches. A recommendation preview with no
fitting candidate exits 0 with a warning; `--apply` then exits 1. Add
`--collection-timeout SECONDS` (30 to 86400) for a broad discovery that needs
more than the default limit. `clear --yes` deletes every local record, or with
`--routing-domain` only that exact domain, in one transaction with one history
entry; OCI is not contacted. Without `--yes` it exits 2 and changes nothing, and
a missing database file exits 1 rather than being created. `cidrctl --help` and
each command's `--help` include workflow guidance.
Keep live-discovery databases and exported backups in a protected directory,
not a shared one such as `/tmp`, and transfer JSON files rather than
synchronizing a live SQLite database through shared folders.

## Sample data, history and OCI records

**Explore with fictional sample data** adds sample records, labeled with source
`demo`, only to an empty inventory. **Remove sample data** in the inventory
table header removes all of them in one change; it is refused if one of your
records uses a sample network as its parent. Records imported from OCI keep
their observed fields read-only in the editor; refresh from OCI to update them,
and edit status, parent, customer, owner, environment and notes locally. A
parent with children cannot be deleted until the children are deleted or
re-parented. History shows the latest 100 changes, with **Load more** when
older changes exist.

To start over, select **Clear inventory…** (the delete icon in the inventory
table header). Choose **Everything** or **Only routing domain** (the current
domain filter is preselected), optionally **Export backup first**, then type
`CLEAR` to enable **Delete N records**. The records are deleted from the local
database in one change; history is kept and OCI is not touched. Discovering or
importing again restores observed networks, but not local planning fields such
as owner, status and notes. If `cidrctl` changed the inventory after the dialog
opened, nothing is deleted and the current records are shown for review.

## Appearance

Open **Settings** with the gear icon in the workspace header, **CIDR Atlas >
Settings…** or ⌘, (Command-comma). Under **Appearance**, choose:

- **System** (the default) to follow the current macOS appearance, including
  automatic switching during the day;
- **Light** for the light theme;
- **Dark** for the original dark theme.

The choice applies immediately, without closing Settings or reopening the app,
and is remembered for the next launch. It is kept in the app's user defaults
(domain `dev.cidratlas.desktop`, key `theme.appearance`), not in the inventory
database, so exports, imports and **Clear inventory…** do not change it and
`cidrctl` does not read it. `defaults delete dev.cidratlas.desktop theme.appearance` resets it to
System.
