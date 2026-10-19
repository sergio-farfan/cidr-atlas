<!--
CIDR Atlas
dev.to article source (title, tags and cover image are set in the dev.to editor).
Author: Sergio Farfan <sergio.farfan@gmail.com>
-->

Every enterprise OCI estate I have worked on ends up with the same artifact: a spreadsheet of CIDR blocks. One tab per region, a few colour-coded rows marked "reserved", a column called *notes* that nobody trusts, and a growing suspicion that the sheet and the tenancy stopped agreeing months ago. The question that matters, "can I give this new VCN `10.64.32.0/20`?", turns into an afternoon of console tabs, the sheet, and a message to whoever set up the DRG.

The failure mode is quiet. Two teams pick the same `/16` in different compartments, nothing complains, and the overlap only surfaces when someone attaches both VCNs to the same DRG, or a VPN to the on-premises network that already uses the range.

So I built **CIDR Atlas**: a local-first CIDR inventory and allocation planner for OCI networks, with a macOS app and a desktop CLI that share one engine and one local SQLite database. It discovers VCNs and subnets through your existing OCI CLI, checks overlaps inside explicit routing domains, and recommends free space with exact IPv4 and IPv6 arithmetic.

> **[0.4.0 is out](https://github.com/sergio-farfan/cidr-atlas/releases/tag/v0.4.0).** It makes imports and exports safer, canonicalizes OCI region keys, adds retries and collection limits to discovery, a centred progress panel, Clear inventory, and a System/Light/Dark appearance setting. [What 0.4.0 changed](#what-040-changed) has the details.
>
> Want to try it? **[Download CIDR-Atlas.dmg →](https://github.com/sergio-farfan/cidr-atlas/releases/latest/download/CIDR-Atlas.dmg)**, open it, and drag CIDR Atlas to Applications.

![CIDR Atlas address inventory dashboard](https://raw.githubusercontent.com/sergio-farfan/cidr-atlas/d129ef3f3514648877f0f2144a43adcea7d5f763/docs/screenshot.png)

---

## Features

- **One inventory** of allocations, VCNs and subnets with routing domain, status (planned, reserved, active, retired), owner, environment, notes and OCI identity. A VCN with several CIDR blocks becomes several records sharing one resource identity.
- **Conflict review scoped by routing domain**, with explicit parents and OCI VCN/subnet identity deciding which overlaps are legitimate
- **Visual address planner** — free and blocked space on a zoomable map, exact slot totals, bounded recommendations, and OCI IPv4 subnet sizing from current or peak demand plus growth
- **CIDR inspector** — mask, range, exact address counts, OCI assignable range and containing supernets, for IPv4 and IPv6
- **Live OCI discovery** across one, several or all READY subscribed regions, and one or all accessible compartments, with progress, cancellation and collection limits
- **Offline imports** of CSV, CIDR Atlas JSON backups and OCI JSON, all through the same preview and atomic apply
- **Safe exports** to JSON and CSV, and **Clear inventory** for everything or one routing domain behind an explicit confirmation
- **History** of local changes and import provenance
- **`cidrctl`**, a CLI for list, check, reserve, recommend, import, discover, export, history and clear, with stable exit codes for scripting

---

## The Stack

The app is **Flutter on macOS**, but most of the code is not Flutter at all. The repository is four pure Dart packages and one app:

- `cidr_core` — CIDR parsing and arithmetic, the record model, hierarchy and conflict rules, the address planner. No Flutter, no I/O.
- `cidr_data` — SQLite storage, atomic imports, CSV/JSON codecs, audit history.
- `cidr_oci` — a read-only adapter that drives the user's installed OCI CLI. It depends on neither of the packages above and cannot write inventory.
- `cidr_cli` — `cidrctl`, a second client of the same core and data packages.
- `apps/cidr_atlas` — the Flutter desktop app.

That split is the point. The rule "is this range free?" lives in exactly one place, and the planner map in the app and `cidrctl recommend` call the same `AddressPlanner.plan`. UI geometry never decides availability. The same engine is ready for the platforms that come next without being rewritten.

Storage is a single SQLite file in `~/Library/Application Support/cidr_atlas/inventory.sqlite`, shared by the app and the CLI. There is no account, no service and no telemetry. OCI is contacted only when you start a discovery.

---

## Routing Domains, Not Tenancies

The first design decision was what "overlap" means. Two VCNs with the same CIDR in different tenancies can be perfectly fine, or a production incident waiting for its DRG attachment. Tenancy and compartment boundaries are administrative; what matters is whether the networks can route to each other.

So every record carries an explicit **routing domain**, and conflict checks only compare records inside the same domain (and the same IP version). Networks joined by a DRG, a VPN, FastConnect or another cloud share a domain; an isolated lab can reuse `10.0.0.0/16` in its own domain without generating noise. The CLI warns when you check a range against a routing domain that has no records, and suggests near matches, because a typo like `example-corprate` would otherwise make everything look free.

---

## Containment Is Not Hierarchy

The second rule is the one that catches most homegrown tools out: **a range being numerically inside another range does not make it a child**.

`10.64.1.0/24` sits inside `10.64.0.0/16`, but that doesn't mean the subnet was carved from that allocation. It may belong to a VCN that somebody created from the same space without asking. CIDR Atlas treats containment as legitimate only when:

- the record names its parent explicitly (`parentId`), forming a valid chain of allocation → VCN → subnet, or
- OCI says so: the subnet's `vcn-id` matches the VCN's OCID, in the same tenancy, region and routing domain.

Anything else that overlaps is reported as a conflict for review.

![Routing conflicts: duplicate and unapproved overlaps inside one routing domain](https://raw.githubusercontent.com/sergio-farfan/cidr-atlas/e2a7cf312d8611e7781f078683f5eddf7a655d83/docs/screenshot-conflicts.png) Structural problems such as cycles, a subnet whose parent is an allocation, or a child outside its parent's range are hard validation errors.

---

## Exact Arithmetic, Including IPv6

IPv6 addresses are 128-bit integers, which rules out doubles and makes "count the free addresses" dangerous if you ever enumerate them. CIDR Atlas does all network arithmetic with `BigInt` and never enumerates address space: free and blocked space are disjoint intervals, and slot totals are computed, not counted. A `/0` IPv6 pool planned for `/128` slots with thousands of blockers is exact and fast.

Input is strict on purpose. `10.64.1.3/24` is rejected with "Host bits are set. Use 10.64.1.0/24." instead of being silently changed into a different network, and a prefix length with leading zeros (`10.0.0.0/08`) is rejected too. Reserving a range you didn't type is how address plans drift.

For OCI IPv4 subnets the planner applies Oracle's rules: `/16` to `/30`, with three addresses reserved per subnet. Demand sizing is explicit about growth: 100 addresses plus 20% growth plus 4 additional is 124 assignable addresses, so the planner picks a `/25` (125 assignable after the three reserved). Oracle's documentation disagrees with itself about IPv6 reservations, so CIDR Atlas shows exact IPv6 totals and deliberately omits an assignable-host figure rather than guessing.

![The visual address planner: planning inputs and the address hierarchy](https://raw.githubusercontent.com/sergio-farfan/cidr-atlas/e2a7cf312d8611e7781f078683f5eddf7a655d83/docs/screenshot-planner.png)

---

## From O(n²) to a Sweep

The first conflict checker compared every record with every other record. That was fine for a few hundred records and quietly terrible at enterprise scale: an inventory of 10,000 records took **about 4.3 seconds**, and it ran on every app refresh and inside the SQLite write transaction of every reservation.

The replacement buckets records by routing domain and IP version, sorts each bucket by network address, and sweeps it with an active list:

```dart
bucket.sort((a, b) {
  final start = a.network.networkAddress.compareTo(b.network.networkAddress);
  return start != 0 ? start : a.index.compareTo(b.index);
});
final active = <_Entry>[];
for (final current in bucket) {
  final start = current.network.networkAddress;
  active.removeWhere((entry) => entry.network.lastAddress < start);
  // Every remaining active entry starts no later than [current] and
  // ends at or after its start, so the two ranges overlap.
  for (final other in active) {
    // ...check explicit and OCI ancestry, record the pair if unrelated
  }
  active.add(current);
}
```

Ancestry, the expensive part, is now evaluated only for pairs that actually overlap. The same 10,000-record OCI hierarchy is checked in **about 33 milliseconds**. A sibling, `conflictsFor(changedIds, records)`, checks only the records a write touches, which is what the reservation transaction needs.

The risky part of a rewrite like this is subtle behaviour change, so the old nested loop lives on as a test oracle. Fifteen hundred seeded random inventories, mixing IPv6, retired records, explicit parents, OCI-inferred subnets and multi-CIDR VCNs, must produce identical results, including which record is reported first and the order of the list.

---

## Driving the OCI CLI Without Trusting the Environment

Discovery uses the OCI CLI you already have, so CIDR Atlas never handles credentials. It reads only the profile name, tenancy, region and whether the profile uses a session token, and it never opens key or token files. That still leaves a lot of ways for a subprocess to do something you didn't intend, so every request is built explicitly:

```dart
final safeEnvironment = <String, String>{
  for (final entry in environment.entries)
    if (!entry.key.toUpperCase().startsWith('OCI_') ||
        entry.key == 'OCI_CLI_CERT_BUNDLE')
      entry.key: entry.value,
};
running = runner(OciCommand(
  executable: connection.executable,
  arguments: [
    '--config-file', connection.configFile,
    '--profile', connection.profile,
    '--auth', authMode,
    '--region', region,
    '--output', 'json',
    '--cli-rc-file', '${temporary.path}/empty_rc',
    '--connection-timeout', '10',
    '--read-timeout', '15',
    '--max-retries', '3',
    ...suffix,
  ],
  environment: safeEnvironment,
  ...
));
```

No shell is involved (an executable plus an argument array), the parent environment is not inherited, inherited `OCI_*` overrides are dropped except the certificate bundle, and an empty rc file keeps someone's `~/.oci/oci_cli_rc` defaults from silently changing the scope. Each command has a deadline, the whole collection has one too, and cancellation or a timeout returns nothing applicable rather than a partial bundle.

Three details took real digging:

- **`--max-retries` counts attempts, not retries.** In OCI CLI 3.94.1 the flag maps to the SDK's `max_attempts`, where `1` means a single attempt and no retry. An earlier version passed `1` believing it allowed a retry, which meant one transient 429 anywhere voided an entire multi-region run. It now passes `3`, and the deadlines are sized so three attempts fit.
- **Region keys are aliases.** The CLI happily accepts `--region iad` for `us-ashburn-1`. Stamping the typed string onto resources made the same VCN appear twice, under two "regions", as a conflict with itself. Region keys are now resolved through the tenancy's region subscriptions before collection, and refreshes match records by OCID.
- **An empty list prints nothing.** For a list with no results, the CLI's renderer writes no output at all, not `{"data": []}`. A successful blank response is therefore accepted only for the four known list commands; an empty response to a `get` is still an error.

All of this runs against fake runners in tests, plus a set of tests that spawn real child processes to prove that both output streams are drained, stdin is closed and a timed-out child is actually killed.

---

## Imports That Never Delete

Discovery and file imports share one path: parse into a preview, show validation errors, warnings and conflicts, then apply the whole batch in a single SQLite transaction or not at all.

Two rules make refreshing a live inventory safe:

1. **A missing resource is not a free range.** An import that doesn't mention a VCN never deletes or retires it. Partial scans, IAM-hidden compartments and narrower scopes are normal, and treating absence as deletion is how a planner ends up recommending space that is in use.
2. **Observed data and planning data are different.** An OCI refresh updates what OCI owns (name, compartment, observation time) and keeps what you own: owner, notes, status, parent, environment and customer.

The transaction wrapper is small, but one detail matters. SQLite rolls back on its own for some failures, such as a full disk or an I/O error, and a second `ROLLBACK` then fails and hides the real cause:

```dart
void _transaction(void Function() body) {
  _database.execute('BEGIN IMMEDIATE');
  try {
    body();
    _database.execute('COMMIT');
  } catch (error, stack) {
    if (!_database.autocommit) {
      try {
        _database.execute('ROLLBACK');
      } catch (_) {}
    }
    Error.throwWithStackTrace(error, stack);
  }
}
```

Reservations take the strictest path: the duplicate-ID check, structural validation and the conflict check all happen inside the same write transaction, so a reservation made from a stale plan is refused instead of creating an overlap. Imports, on the other hand, keep real discovered conflicts and show them for review. Hiding a real overlap would be worse than reporting it.

---

## What 0.4.0 Changed

0.4.0 started as a whole-repository review against the project's own rules, which turned up 70 confirmed findings. The ones that would have hurt real users:

- `cidrctl export --file` could overwrite the open database. Exports now refuse the database and its SQLite side files, write atomically and keep the earlier file's permissions.
- A CSV with fewer columns, matched by ID, silently erased owner, notes and the OCI resource ID. Only the columns present in the file are now merged.
- CSV exports now escape cells that a spreadsheet would evaluate as formulas, since VCN display names can be set by anyone with network rights in the tenancy.
- The region-alias duplicates and the retry trap described above.

On the app side, discovery now shows a **centred progress panel** with the current step, region/compartment scope counts, elapsed time, the collection limit and Cancel. When a direct-compartment scan of the tenancy root comes back empty (root usually holds no networks), the preview offers **Retry with all accessible compartments**. **Clear inventory** removes everything or one routing domain in one transaction after an export prompt and a typed confirmation. And **Settings** (⌘,) offers System, Light and Dark: the existing dark look moved into a semantic palette unchanged, and a new light palette was checked for WCAG contrast.

The test suite grew from 332 to **580** tests across the five packages.

---

## Before You Start

You can use CIDR Atlas without any OCI access: add records by hand or import a CSV, a JSON backup or an OCI JSON file. Live discovery needs:

- the OCI CLI (`brew install oci-cli`) and a profile in `~/.oci/config`, from `oci setup config` (API key) or `oci session authenticate` (browser session)
- read-only access; every request needs only the `inspect` verb:

```text
Allow group NetworkViewers to inspect tenancies in tenancy
Allow group NetworkViewers to inspect compartments in tenancy
Allow group NetworkViewers to inspect virtual-network-family in tenancy
```

The README's [Before you start](https://github.com/sergio-farfan/cidr-atlas#before-you-start) section covers profiles, session tokens and the import formats with examples.

---

## Build & Install

**Easiest:** **[download CIDR-Atlas.dmg](https://github.com/sergio-farfan/cidr-atlas/releases/latest/download/CIDR-Atlas.dmg)** (or browse the [latest release](https://github.com/sergio-farfan/cidr-atlas/releases/latest)), open it and drag **CIDR Atlas** to **Applications**. The disk image is universal for **Apple silicon and Intel**. New installations start empty; there is optional, clearly labelled fictional sample data to explore.

CIDR Atlas is **ad-hoc signed and not notarized**. After verifying the download against the release checksum and attempting to open it, you may need **System Settings → Privacy & Security → Open Anyway**. See [Apple's first-launch instructions](https://support.apple.com/en-lamr/102445).

**From source**, with Flutter 3.47 or newer and Xcode:

```bash
git clone https://github.com/sergio-farfan/cidr-atlas.git
cd cidr-atlas/apps/cidr_atlas
flutter pub get
flutter run -d macos
```

The CLI runs from source with `scripts/cidrctl`, or builds as a standalone executable with `scripts/build_cli.sh`:

```bash
./scripts/cidrctl --db ~/tmp/demo.sqlite import csv --file examples/fictional_inventory.csv --apply
./scripts/cidrctl --db ~/tmp/demo.sqlite recommend \
  --pool 10.90.0.0/20 --routing-domain example-connected \
  --addresses 100 --growth-percent 20 --additional 4 --policy oci_ipv4 --kind subnet
```

---

## Source Code

CIDR Atlas is on GitHub: [github.com/sergio-farfan/cidr-atlas](https://github.com/sergio-farfan/cidr-atlas), MIT licensed.

---

*Built with Flutter, Dart and SQLite on macOS.*
