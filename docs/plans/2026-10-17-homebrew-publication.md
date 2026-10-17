# CIDR Atlas — Homebrew publication plan (2026-10-17)

Author: Sergio Farfan <sergio.farfan@gmail.com>

Publish CIDR Atlas through the existing personal tap
(`github.com/sergio-farfan/homebrew-tap`, working clone `~/projects/git/homebrew-tap`),
the same channel as `alttab` and `nosleep`:

```bash
brew install --cask sergio-farfan/tap/cidr-atlas
```

The reusable procedure is `~/projects/git/HOMEBREW-TAP-PROCEDURE.md` (verified
2026-09-13, Homebrew 7.0.1). This plan records only what differs for CIDR Atlas.
Decisions taken with the maintainer: make the repository public first, and ship
`cidrctl` inside the disk image so the cask installs the CLI as well.

## What differs from the sibling apps

| Aspect | alttab / nosleep | CIDR Atlas |
| --- | --- | --- |
| Repository | public | **private today — blocks the cask** |
| Release build | GitHub Actions `release.yml` | local, by the maintainer (`docs/releasing.md`) |
| Tap bump trigger | `repository_dispatch` from CI with `TAP_DISPATCH_TOKEN` | `gh api .../dispatches` from the maintainer's machine; no new secret |
| Payload | one `.app` | `.app` **plus** two per-architecture `cidrctl` executables (arch-selected `binary` stanza) |
| User data | preferences only | a shared SQLite inventory the CLI uses too — kept out of `zap` |

### Gate: repository visibility

A cask URL is fetched with plain curl and carries no GitHub credentials, and
Homebrew has no private-release download strategy (checked: no
`PrivateRepositoryRelease` under `$(brew --repository)/Library/Homebrew`). While
`cidr-atlas` is private:

- `brew fetch --cask` and `brew install --cask` return 404 for everyone;
- `brew audit --cask --online` fails on both the asset and the homepage check;
- the tap's `tests.yml` audits the **whole tap**, so pushing this cask would
  turn the `alttab` and `nosleep` runs red.

Nothing is pushed to `homebrew-tap` until `gh repo view --json visibility`
reports `PUBLIC`.

## Facts pinned for the cask

| Value | Source |
| --- | --- |
| token `cidr-atlas` | free: `brew info --cask cidr-atlas` → no such cask; `brew search cidrctl` finds no formula shipping `bin/cidrctl`, so the `binary` symlink cannot collide |
| `app "CIDR Atlas.app"` | bundle name in `scripts/build_dmg.sh` (contains a space) |
| `binary "cidrctl-arm64"` / `cidrctl-x86_64` | new DMG payload, phase 1 — **no universal binary is possible**, see Phase 1 |
| bundle id `dev.cidratlas.desktop` | `apps/cidr_atlas/macos/Runner/Configs/AppInfo.xcconfig:11` |
| `depends_on macos: :monterey` | confirmed: the 0.4.0 release build's `LSMinimumSystemVersion` is `12.0` (PlistBuddy on the built bundle, 2026-10-17), which is what `brew audit --online` compares |
| `url` | `.../releases/download/v#{version}/CIDR-Atlas-#{version}.dmg` — the versioned asset, not the stable copy |
| `sha256` | first field of `CIDR-Atlas-X.Y.Z.dmg.sha256` |
| `desc` | `Local-first IP address inventory and CIDR allocation planner` — under 80 chars, no app name, no "macOS" (Cask `Desc` audit) |
| `livecheck` | `url :url`, `strategy :github_latest` — required: 0.1.0–0.3.0 are prereleases, only 0.4.0 is Latest |
| `zap` | **`~/Library/Preferences/dev.cidratlas.desktop.plist` only** — the inventory is deliberately excluded, see below; confirm the rest with `brew generate-zap` |

Asset naming already satisfies the procedure's prerequisite: the filename embeds
the version and a `.sha256` is published next to it.

### Decision: `zap` does not delete the inventory

`~/Library/Application Support/cidr_atlas` holds the inventory that the app and
`cidrctl` share. Listing it under `zap trash:` would make
`brew uninstall --cask --zap cidr-atlas` destroy the user's records, and would
make the local validation step and the tap's CI smoke test dangerous on the
maintainer's own machine. It is therefore excluded: `zap` removes the
preferences only, and the caveats point at the README's existing opt-in
`rm -rf "$HOME/Library/Application Support/cidr_atlas"` step (`README.md:812`),
which already treats inventory deletion as a separate, deliberate action. The
cask's `zap` then matches CI exactly, with no special-case warning.

## Phase 0 — make the repository public

Maintainer action, outside this plan's edits. Afterwards:

Every mention of the repository being private has to go or be reworded
(`grep -rni private README.md PROJECT.md docs CHANGELOG.md dev-to-article.md`,
filtering the unrelated "private key"/"privacy" hits):

- `README.md:34` — "While the repository is private, downloading requires
  repository access."
- `README.md:235` — "Clone the private source repository".
- `docs/releasing.md:39` — the no-release-workflow rationale cites "a private
  repository"; the cost argument still holds, so reword rather than delete.
- `docs/releasing.md:258` — the `/releases/latest/download/` link working only
  for signed-in users.
- `docs/architecture.md:311` — "private repository's GitHub Releases".
- `PROJECT.md:243` — "The repository remains private."
- `docs/design/2026-10-15-expanded-oci-discovery.md:73` — a historical design
  note; leave it, it records what was true then.
- Re-check that no release asset or committed file carries customer data,
  credentials or machine-specific SDK paths before flipping visibility.

## Phase 1 — ship `cidrctl` in the disk image (`cidr-atlas`)

The app is universal; the CLI must cover both architectures too, or Intel users
get a broken `cidrctl`. `scripts/build_cli.sh` compiles for the host only.

Two facts were established empirically on 2026-10-17 with Flutter 3.47.7 /
Dart 3.13.5 on macOS 27.0.1 arm64, and they decide the design:

1. **`dart compile exe` cannot cross-compile to macOS x64.**
   `--target-arch x64 --target-os macos` fails with
   `Unsupported target platform macos_x64. Supported target platforms:
   linux_arm, linux_arm64, linux_riscv64, linux_x64`. The x86_64 slice therefore
   has to be built by an x64 Dart SDK of the **same version** running under
   Rosetta (`arch -x86_64 ~/development/dart-sdk-x64/bin/dart`), which is
   installed and verified.
2. **`lipo` destroys a Dart AOT executable.** Both single-arch binaries print
   `cidrctl 0.4.0`, but the `lipo -create` result prints
   `Dart SDK version: 3.13.5 ... on "macos_arm64"` — the appended AOT snapshot is
   no longer found at the offset the runtime expects, so the fat binary degrades
   to a bare `dartaotruntime` with no payload. Re-signing does not help; the
   payload, not the signature, is what breaks. **There is no universal
   `cidrctl`.**

So the design is two per-architecture executables, selected at install time:

1. `scripts/build_cli.sh --both` (or similar) builds `cidrctl-arm64` with the
   Flutter-bundled Dart and `cidrctl-x86_64` with `arch -x86_64 "$DART_X64_BIN"`.
   Per `AGENTS.md` ("no silent toolchain installation") the script requires
   `DART_X64_BIN`, checks that its `--version` matches the arm64 SDK's, and exits
   with an explanatory message when either condition fails — it never downloads
   an SDK. The plain `build_cli.sh` keeps building only for the current Mac.
2. `scripts/build_dmg.sh` copies both into the image and extends the
   mounted-image checks: each file present and executable, `lipo -archs` reports
   the expected single architecture, `codesign --verify --strict` passes, and
   `codesign --verify --strict` passes (both slices are emitted
   `adhoc, linker-signed` with no team identifier, verified 2026-10-17 — no
   explicit `codesign` step is needed as long as nothing rewrites the file), and
   each binary's `--version` equals the app's `CFBundleShortVersionString`
   (`arch -x86_64` for the Intel one — which also means the check only runs where
   Rosetta is available; skip it with a printed note otherwise).
3. `INSTALL.txt` tells drag-install users which file to copy and that the
   quarantine flag has to be cleared.

This also moves the CLI version check into release packaging, replacing the
manual `build/cidrctl --version` step in `docs/releasing.md` §3.

## Phase 2 — the cask (`homebrew-tap`)

`Casks/cidr-atlas.rb`, stanza order per the Cookbook, modelled on
`Casks/nosleep.rb`:

- `app "CIDR Atlas.app"`, plus an architecture-selected CLI symlink:

  ```ruby
  binary "cidrctl-#{on_arch_conditional arm: "arm64", intel: "x86_64"}", target: "cidrctl"
  ```

  `Cask::DSL` includes `OnSystem::MacOSAndLinux`, which defines `on_arm`,
  `on_intel` and `on_arch_conditional(arm:, intel:)`
  (`$(brew --repository)/Library/Homebrew/on_system.rb:52-76`,
  `cask/dsl.rb:143`), so one cask serves both architectures from the one
  universal DMG. Confirm `brew style` accepts the interpolated source with
  `target:` before pushing.
- `uninstall quit: "dev.cidratlas.desktop"` (no login item, no LaunchAgent).
- `zap trash:` as above — an array, so `brew style` is satisfied.
- `caveats`: the ad hoc signing first-launch step with the **Open Anyway**
  wording and `xattr -dr com.apple.quarantine` alternative, the fact that the
  prompt returns after every `brew upgrade` (ad hoc `cdhash` requirement cannot
  carry a Gatekeeper approval forward), the equivalent `xattr` step for the
  quarantined `cidrctl` on first run from a shell (undecided: Homebrew's
  `cask/artifact/binary.rb` mentions quarantine nowhere, so **verify
  empirically** after install with
  `xattr -p com.apple.quarantine "$(readlink -f "$(brew --prefix)/bin/cidrctl")"`
  and write the caveat to match the observed behavior — assert neither outcome
  in advance), and a pointer to the README for removing the inventory by hand.
- No `verified:`, no `auto_updates`, no `conflicts_with` (no other cask installs
  `CIDR Atlas.app`), symbol form for `depends_on macos:`.

## Phase 3 — tap wiring (`homebrew-tap`)

Replicate the shape of commit `8db8e97` ("Add nosleep cask (1.2.0)"):

- `.github/workflows/bump.yml`: `types: [alttab-release, nosleep-release, cidr-atlas-release]`.
- `.github/workflows/tests.yml`: add `cidr-atlas` to the smoke-test loop
  (`brew install --cask` / `brew uninstall --cask --zap`), which also exercises
  the `binary` symlink.
- `README.md`: install line, table row, and an ad hoc signing paragraph in the
  style of the existing two, mentioning that this cask also installs a
  `cidrctl` command.

The bump workflow needs no change beyond the dispatch type: its version regex
(`^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$`) already accepts `0.4.0`.

## Phase 4 — app-repo documentation (`cidr-atlas`)

- `README.md` **Download**: Homebrew as the first install option, the trust note
  (`brew trust sergio-farfan/tap && brew tap sergio-farfan/tap` for short names,
  trust *before* tap), `brew upgrade --cask cidr-atlas`, the Open-Anyway note
  with its repeat-after-every-upgrade caveat, and the DMG as the second option.
  Mention that the cask also installs `cidrctl`.
- `README.md` **Uninstall**: `brew uninstall --cask --zap cidr-atlas` next to
  the existing manual steps, stating that it leaves the inventory in place and
  that deleting it is still the separate, deliberate step already documented
  there. Mirror the wording of `~/projects/git/nosleep/README.md:17-34`
  ("Option 1 — Homebrew (recommended)"), which is the house style for these
  install sections.
- `docs/releasing.md`: a new step 8 — bump the tap after verifying the release:

  ```sh
  VERSION=X.Y.Z
  SHA="$(cut -d' ' -f1 "build/releases/CIDR-Atlas-$VERSION.dmg.sha256")"
  jq -n --arg v "$VERSION" --arg s "$SHA" \
    '{event_type: "cidr-atlas-release",
      client_payload: {cask: "cidr-atlas", version: $v, sha256: $s}}' \
    | gh api repos/sergio-farfan/homebrew-tap/dispatches --input -
  ```

  plus the manual `sed` fallback from the procedure's §5, the
  `brew livecheck --cask sergio-farfan/tap/cidr-atlas` drift check, and a note
  that prereleases must **not** be dispatched (livecheck follows the GitHub
  Latest release, so the cask and the audit would disagree).
  Also extend §3 with the new universal-CLI build step.
- `CHANGELOG.md` under `[Unreleased]` → **Added**: Homebrew cask install channel
  and `cidrctl` in the disk image.
- `PROJECT.md`: verification counts if tests change, release status, next action.

Leave `~/projects/git/HOMEBREW-TAP-PROCEDURE.md` untouched; it is shared across
projects and already covers this case.

## Phase 5 — verification

Before pushing the tap:

```sh
ruby -c Casks/cidr-atlas.rb
brew trust sergio-farfan/tap && brew tap sergio-farfan/tap   # trust BEFORE tap
brew fetch --cask sergio-farfan/tap/cidr-atlas               # URL + sha256
brew info --cask sergio-farfan/tap/cidr-atlas                # deprecation warnings
brew install --cask sergio-farfan/tap/cidr-atlas
cidrctl --version                                            # both arches: lipo -archs "$(readlink -f "$(brew --prefix)/bin/cidrctl")"
xattr -p com.apple.quarantine "$(readlink -f "$(brew --prefix)/bin/cidrctl")" || true
brew uninstall --cask --zap cidr-atlas
```

A hand-installed `CIDR Atlas.app` already in `/Applications` makes
`brew install --cask` fail, and `--adopt` does not help: it only adopts a
*byte-identical* bundle, which this one will not be (the cask points at the
newer, CLI-carrying release). Move the existing copy aside before the install
test and put it back, or remove it.

With the inventory excluded from `zap` (see the decision above), `--zap` is safe
to run here and exercises the same path as CI. Confirm afterwards that
`~/Library/Application Support/cidr_atlas/inventory.sqlite` still exists and
that `$(brew --prefix)/bin/cidrctl` is gone.

`brew style`, `brew audit --cask --online --strict --tap` and `brew readall`
need Homebrew's developer gems; run them if they work on this machine,
otherwise rely on `tests.yml` (procedure §11 records the gem failure mode).

## Order of work

1. Phase 0 (maintainer) — repository public.
2. Phase 1 — universal `cidrctl` in the DMG, verified locally. This changes the
   release payload, so it needs a new release (0.4.1 or 0.5.0) before the cask
   can point at an asset that contains the CLI.
3. Phases 2–3 — cask and tap wiring against that release; tap CI green.
4. Phase 4 — documentation.
5. Phase 5 — install verification on this machine.

A cask pointing at the current 0.4.0 asset would install the app only: that
release's DMG contains no `cidrctl`. Publishing now and adding the CLI later is
the worse option, because `bump.yml` runs `brew bump-cask-pr`, which rewrites
only `version` and `sha256` — it cannot add a `binary` stanza, so that route
needs a hand-written tap commit anyway. **Decision: hold the cask until the
release that carries the universal CLI**, so the cask is correct from its first
commit.
