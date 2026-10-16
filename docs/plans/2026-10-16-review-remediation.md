# CIDR Atlas — review remediation plan (2026-10-16)

Author: Sergio Farfan <sergio.farfan@gmail.com>

A whole-repository review against `AGENTS.md`, `docs/CONTRACT.md` and
`docs/architecture.md` produced 70 verified findings (4 high, 19 medium, 47 low)
after adversarial verification; 7 further claims were refuted. Duplicates are
merged below. Finding numbers (`#n`) refer to the review ledger.

Triage rule: fix confirmed defects. Where a fix would weaken a documented safety
property, change a documented contract, or add a feature, apply the conservative
variant now and record the remainder under **Deferred decisions**.

## Baseline (before remediation)

Analyzers clean. Tests: core 50, data 78, OCI 82 + 1 failing
(`does not inherit unspecified environment values` assumes `PUB_CACHE` is set),
CLI 49, app 72.

## Wave 1 — `packages/cidr_core`

- [x] #10/#17 `InventoryRules.conflicts` is O(n²): per-domain/version sorted sweep,
      `vcnsByResourceId` index, identical `Conflict` orientation and ordering
      (old loop kept as a randomized test oracle); add `conflictsFor(changedIds, records)`.
- [x] #41 explicit VCN parent accepted when `subnet.vcnId` names a different VCN in the inventory.
      Final rule: only a comparable VCN (not retired, same routing domain, same
      tenancy/region where both are set) contradicts the link.
- [x] #42/#60 strict observation time: reject calendar rollover; shared
      `parseObservationTime` helper; UTC output; store reads stay tolerant.
- [x] #43 reject leading zeros in the prefix length (`/08`).
- [x] #44 `available()` without `parentId` throws a raw `FormatException` for malformed records.
- [x] #46 boundary tests: demand ceilings, IPv6 OCI-inferred blockers, multi-CIDR VCN inference.

## Wave 1 — `packages/cidr_oci`

- [x] #3 canonicalize regions (lowercase, full identifier; short keys mapped via
      subscriptions when available, otherwise rejected with guidance); dedupe after
      canonicalization.
      The collection limit is recomputed after key resolution. No `cidr_data` refresh test
      with a canonicalized region was added.
- [x] #20 `--max-retries 1` means one attempt in OCI CLI 3.94.1: use 3 attempts, with
      connection/read timeouts and a per-command deadline that fit.
- [x] #22 profile parser: header trailing comments, indented continuation lines.
- [x] #6 `OciCompartment.parentId` and display path for same-named compartments.
- [x] #68 `~` expansion for explicit executable; `$HOME/bin/oci` candidate.
- [x] #69 compartment `name` optional (fall back to the id).
- [x] Known failing `PUB_CACHE` test made environment-independent; #47 loosen wall-clock margins.

## Wave 2 — `packages/cidr_data`

- [x] #1 id-matched CSV with fewer columns erases fields: merge only present columns.
      Follow-up: JSON backup records with missing keys still replace the whole record
      (documented).
- [x] #2 id-less CSV collisions: row-numbered error; warn when an id-less row replaces a different record.
- [x] #13 warn when a locally retired record is still observed live by OCI.
- [x] #58 warn when a bundle is older than existing observations.
- [x] #14 CSV formula-injection escaping with lossless round trip.
- [x] #15 guarded `ROLLBACK` preserves the original error.
- [x] #61 canonical CIDR alias dedupe; #62 warn on truncated raw OCI pages (`opc-next-page`).
- [x] #16/#33 shared `defaultDatabasePath` in `cidr_data`; macOS path byte-identical to v0.3.0.
      Linux ignores a relative or empty `XDG_DATA_HOME`; `package:cidr_cli` re-exports the
      function.
- [x] #32 refuse deleting a parent with children with an explanatory message.
- [x] #34 (store side) `deleteAll(ids)` validated once, for removing demo data.
- [x] Use `conflictsFor` inside the write transaction; #59 rollback/busy/stale/partial-CSV tests.
      OCI `metadata.collectedAt` stays tolerantly parsed; CSV and backup `verifiedAt` are
      strict.

## Wave 3 — `packages/cidr_cli`

- [x] #0 `export --file` refuses the open database (and `-wal/-shm/-journal`); temp-file + rename write.
      Carry-over: the replacement keeps the earlier file's mode; dangling symlinks are
      followed.
- [x] #8/#11/#65 `reserve` uses `InventoryStore.reserve`.
- [x] #9/#38/#45 stderr warnings: new empty database created; routing domain with no records,
      naming case-insensitive near matches. Exit codes unchanged.
- [x] #12 successful empty discovery exits 0 with a neutral message.
- [ ] #37 resolve and validate the database path before OCI collection.
      Partial: an existing but unwritable ancestor directory is still detected only after
      collection; the error now names the path.
- [x] #39 usage-error consistency; #40 `defaultDatabasePath` tests; #53 version test.
      The optional process-level SIGINT test (#40) was not added. The #53 SDK-floor part is
      deferred (below).
- [x] #18/#21 `--collection-timeout` option; scope count in progress; #49 print the config/profile used.
      Carry-over: the scope line comes from structured `OciDiscoveryProgress` and always
      states the limit.

## Wave 3 — `apps/cidr_atlas`

- [x] #4 planner input validation messages instead of raw Dart exceptions.
- [x] #5/#17 cached hierarchy model; reuse controller conflicts; no per-build JSON signature.
      Optional lazy rendering of very large hierarchies was not done. A refresh now clears
      planner results.
- [x] #6 compartment path display and selected OCID.
- [x] #7 export and demo load act on the current database.
      No widget test for Export all (platform save dialog); the optional refresh-on-focus
      was not implemented.
- [x] #16/#33 app uses the shared default database path.
- [x] #23 Load scopes keeps manual entries; #24 free gaps drawn above blocked space;
      #28 zoom anchoring/duplicate Fit; #29 shared OCI subnet policy helper.
      The IPv6 half of #29 was refuted in review and left unchanged.
- [x] #26 help wording; #27 semantics for candidates, errors, progress.
- [x] #31 editor errors keep form input; #32 explanatory delete refusal.
- [x] #34 demo records labeled `demo` with a remove action; #35 observed OCI fields read-only;
      #36 history paging.
      Carry-over: Load more appears only when older entries exist.
- [x] #18 optional collection timeout in the discovery dialog.
      Carry-over: the client factory is threaded through `AtlasApp` and `ImportDialog`; an
      injected client without a factory gets a dialog-side timer.
- [x] #25/#30 integration tests: planner reservation end to end, delete, edit, import.

## Wave 4 — documentation and hygiene

- [x] Sync `docs/CONTRACT.md`, `docs/architecture.md`, `README.md`, `docs/user-guide.md`,
      `PROJECT.md` with all changes (#48, #49, #50/#66, retries/timeouts, new options).
- [x] #52 examples use `~/tmp`, not `/tmp`; DMG staging under `build/`.
- [x] #54 missing file headers; #55 `scripts/cidrctl` dependency freshness.
- [x] #67 visual-planner plan checkboxes; architecture OCI IPv4 citation.
      Two items stay open in that plan: per-status map patterns and filters (#64), and a
      native reservation smoke.
- [x] #51 consistent lint configuration (separate mechanical step).
- [x] Full format/analyze/test, updated counts, final whole-change review.
      The final review (correctness, security, docs/tests) found three upgrade
      regressions, now fixed: v0.3.0 backups and CSV exports with a zone-less `verifiedAt`
      restore again (read as local time, with a counting preview warning; rollover still
      rejected); OCI identity matches by OCID regardless of region spelling, so v0.3.0
      records under `IAD`/uppercase regions refresh in place with planning fields kept and
      the canonical region (carried to an unobserved linked VCN/subnet); and #41 moved from
      `validate` to the non-blocking `InventoryRules.advisories`, surfaced in import
      previews, CLI `check`/`reserve` stderr and the record editor. Minor fixes: the
      empty-inventory routing-domain warning documented, a read-only `--apply` database
      test, an export test that a failed write keeps the earlier file's bytes,
      `recommend --apply` no-fit prints `No reservation was saved.`, and 5 s sweep budgets.
      Format, analyze and tests are clean in every package (core 72, data 124, OCI 110,
      CLI 83, app 116; 505 total, recorded in `PROJECT.md`).

## Deferred decisions (operator)

- #19 all-compartments mode: continue past a compartment that denies network listing and
  record it as unobserved coverage, instead of failing the whole collection. Changes the
  documented fail-closed contract.
- #0 strict variant: require `--force` to overwrite an existing export file.
- #9 strict variant: read-only commands refuse a nonexistent database instead of warning.
- #45 case-insensitive routing-domain identity.
- #56 release provenance (clean-tree check, source commit in DMG); #57 CI workflow;
  #63 platform gate for OCI discovery on iOS; #64 blocker attribution and planner view filters.
- Broad-mode collection strategy (bounded concurrency or Search pre-filter) beyond the
  timeout option.
- #53 SDK floors: the declared floors (>=3.4/3.5) are below the lockfiles (>=3.11). Raising
  them to >=3.11.0 switches `dart format` to the tall style and reformats about 37 files,
  so the change needs its own reformatting step. Package versions are unchanged.
