<!--
CIDR Atlas
X post source for the project announcement.
Author: Sergio Farfan <sergio.farfan@gmail.com>
-->

Announcement copy for X. The voice follows `dev-to-article.md`: the problem
first, in the first person, then what was built, then plain claims without
superlatives. Every variant below is within the 280-character limit.

Post the single version or the thread, not both. Links resolve only after the
repository is public and the dev.to article is published; until then post
without them or hold the announcement.

## Single post — recommended (268 characters)

Every OCI estate I've worked on runs its IP planning on a spreadsheet nobody
trusts.

So I built CIDR Atlas: a local-first CIDR inventory and allocation planner.
macOS app + CLI, one Dart engine, one SQLite file. Reads your own OCI CLI.
Exact IPv4/IPv6 math. No cloud.

## Single post — alternative, opens on the question (276 characters)

"Can I give this VCN 10.64.32.0/20?"

If answering that takes an afternoon of console tabs and a spreadsheet, I built
CIDR Atlas: a local-first CIDR inventory and allocation planner for OCI. macOS
app + CLI, shared Dart engine, local SQLite. Data never leaves the Mac.

## Thread (237 / 269 / 247 / 157 characters)

**1/** Every OCI estate I've worked on runs its IP planning on a spreadsheet
nobody trusts. One tab per region, a "reserved" column, and a quiet suspicion
the sheet stopped matching the tenancy months ago. CIDR Atlas is what I built
instead.

**2/** It discovers VCNs and subnets through the OCI CLI you already have —
read-only, no new credentials, nothing leaves the machine. Conflicts are scoped
by explicit routing domain, because two teams using 10.0.0.0/16 in separate
domains is fine, and in the same DRG is not.

**3/** Containment doesn't imply approval: a /24 inside a /16 is only a child
through an explicit parent link or an OCI VCN/subnet identity match. The
planner recommends free space with exact IPv4 and IPv6 arithmetic — BigInt, no
float shortcuts.

**4/** macOS app and a cidrctl CLI share one engine and one local SQLite
inventory. Flutter + pure Dart + SQLite, MIT.

Download: https://github.com/sergio-farfan/cidr-atlas/releases/latest/download/CIDR-Atlas.dmg
Write-up: <dev.to article URL>

## Notes

- Avoid the word "IPAM". `docs/design/2026-10-16-ipam-feature-assessment.md`
  places the current feature set at Tier 1 against Infoblox NIOS, so the term
  invites a comparison the product does not yet win.
- Claim only what a release actually ships. The app is ad hoc signed and not
  notarized, so "no cloud" and "local-first" are safe claims while "signed" is
  not.
- Add the Homebrew one-liner
  (`brew install --cask sergio-farfan/tap/cidr-atlas`) to the thread's last
  post once the cask is published; `docs/plans/2026-10-17-homebrew-publication.md`
  tracks that work.
