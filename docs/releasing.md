# Releasing CIDR Atlas

Author: Sergio Farfan <sergio.farfan@gmail.com>

Releases are built, verified and published by the maintainer on a Mac. This page
records that local procedure. Publishing is an explicit maintainer decision made
after reviewing the verification results and any checks still outstanding.

## Policy

- **Versioning.** SemVer. The tag is `vX.Y.Z`; the GitHub release title is
  `CIDR Atlas X.Y.Z` (no `v`, no "preview"). Each new version gets its own tag.
  Never move a published tag or replace published assets to repair a release;
  issue a new version.
- **Assets.** Every release carries three files:
  `CIDR-Atlas-X.Y.Z.dmg`, its checksum `CIDR-Atlas-X.Y.Z.dmg.sha256`, and
  `CIDR-Atlas.dmg`, a stable-name copy with identical bytes so that
  `https://github.com/sergio-farfan/cidr-atlas/releases/latest/download/CIDR-Atlas.dmg`
  always serves the newest installer. The versioned checksum applies to the
  stable copy too. Releases 0.1.0 to 0.3.0 keep their original asset names
  (`CIDR-Atlas-X.Y.Z-macos-universal.dmg`); do not rename them.
- **Signing.** Releases are ad hoc signed and not notarized. The maintainer is not
  enrolled in the Apple Developer Program; Developer ID signing and notarization
  are optional future work, not prerequisites. Release notes state the signing
  status. After opening a checksum-verified download, users may need **System
  Settings > Privacy & Security > Open Anyway**; see
  [Apple's instructions](https://support.apple.com/en-lamr/102445).
- **Channel.** A regular release becomes the repository's latest release. A
  `--prerelease` release does not: `/releases/latest` and
  `/releases/latest/download/...` resolve only to the newest non-prerelease
  release. Releases 0.1.0 to 0.3.0 were all published as prereleases, so the
  stable download link resolves only once a regular release exists.

### Why there is no release workflow

CI (`.github/workflows/ci.yml`) checks formatting, analysis and tests. Packaging is
not automated: the universal app needs Xcode and the DMG needs Apple's `hdiutil`,
`codesign` and `lipo` on macOS. Building releases on a hosted macOS runner would
add a long macOS packaging job without improving the ad hoc signature, so release builds are made and verified locally with the scripts
below.

## 1. Prepare the source

Start from an up-to-date `main` with a clean working tree and a green CI run.

Bump the version in all four places:

| File | Field |
| --- | --- |
| `apps/cidr_atlas/pubspec.yaml` | `version: X.Y.Z+BUILD` (increment the build number) |
| `apps/cidr_atlas/lib/app.dart` | header label `'vX.Y.Z  ·  MACOS PREVIEW'` |
| `packages/cidr_cli/pubspec.yaml` | `version: X.Y.Z` |
| `packages/cidr_cli/lib/cidr_cli.dart` | `const _version = 'X.Y.Z';` |

A CLI test (`--version reports the package version from pubspec.yaml` in
`packages/cidr_cli/test/cli_safety_test.dart`) fails if `_version` and the CLI
pubspec disagree. `cidr_core`, `cidr_data` and `cidr_oci` keep their own
versions.

Make sure `CHANGELOG.md` lists the release's changes under `## [Unreleased]`, and
that user-facing documentation (`README.md`, `docs/user-guide.md`, in-app help)
matches the behavior being released.

## 2. Verify

The SDKs may be outside `PATH`; call them by absolute path or set `DART_BIN` /
`FLUTTER_BIN`. In each of `packages/cidr_core`, `cidr_data`, `cidr_oci` and
`cidr_cli`:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

In `apps/cidr_atlas`:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

From the repository root, check the scripts:

```sh
for script in scripts/*.sh scripts/cidrctl scripts/run_macos.command; do
  bash -n "$script"
done
```

Record the test count of each package for the release notes and `PROJECT.md`.

## 3. Build

Use the full Xcode, not the Command Line Tools. If `xcode-select -p` prints
`/Library/Developer/CommandLineTools`, export the Xcode developer directory for
this shell instead of changing the system setting:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Quit any running copy of CIDR Atlas that was launched from the build folder
(`apps/cidr_atlas/build/macos/Build/Products/Release/CIDR Atlas.app`) before
rebuilding. An app that is open while its bundle is rebuilt leaves the rebuilt
bundle with an invalid signature, and `build_dmg.sh` then fails its
`codesign --verify --deep --strict` check.

```sh
pgrep -fl 'CIDR Atlas.app' || echo 'not running'
```

Make a clean build, then package:

```sh
(cd apps/cidr_atlas && flutter clean)   # or "$FLUTTER_BIN" clean
scripts/build_macos.sh
scripts/build_cli.sh
scripts/build_dmg.sh --skip-build
```

`build_macos.sh` builds the universal (arm64 and x86_64) release app;
`build_cli.sh` builds `build/cidrctl` for the current Mac. `build_dmg.sh` (without
`--skip-build` it runs `build_macos.sh` first) verifies both architectures and the
deep/strict signature of the app, creates the disk image, verifies the image,
mounts it read-only and checks its contents, architectures, version and
signature again, then writes into `build/releases/`:

- `CIDR-Atlas-X.Y.Z.dmg`
- `CIDR-Atlas-X.Y.Z.dmg.sha256` (checked with `shasum -a 256 -c`)
- `CIDR-Atlas.dmg`, a copy confirmed byte-identical with `cmp`

The version in the file names comes from the built app's
`CFBundleShortVersionString`, so a mismatch with the intended version shows here.
Check `build/cidrctl --version` as well. Record any native checks of new UI
(launching the app, the changed dialogs) and the checks not performed.

## 4. Record the release

1. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`,
   remove the "Prepared as X.Y.Z ... not yet published" paragraph, and add a new
   empty `## [Unreleased]` section above it. In the link references at the end,
   point `[Unreleased]` at `compare/vX.Y.Z...HEAD` and add
   `[X.Y.Z]: https://github.com/sergio-farfan/cidr-atlas/releases/tag/vX.Y.Z`.
2. In `PROJECT.md`, update the verification section (toolchain, per-package test
   counts) and the release status: tag, DMG size in bytes and SHA-256, and the
   next action. Fill in the source commit after step 5.

The release commit may change only documentation relative to the tree that was
built. If any source file changes, rebuild and verify again.

## 5. Commit, tag and push

```sh
git status --short
# List the release files explicitly: the version files if not yet committed,
# plus CHANGELOG.md and PROJECT.md.
git commit -m "Release CIDR Atlas X.Y.Z" -- CHANGELOG.md PROJECT.md
git tag -a vX.Y.Z -m "CIDR Atlas X.Y.Z"
git log --format='%h %an %s' origin/main..HEAD   # only the release commits
git push origin main
git push origin vX.Y.Z
```

Commit subjects are sentence-case imperative without type prefixes. Tag the
verified release commit, and confirm the remote tag identifies it:

```sh
git rev-parse 'vX.Y.Z^{commit}'
git ls-remote origin 'refs/tags/vX.Y.Z^{}'
```

## 6. Publish

Write the release notes to a scratch file outside the repository, for example
`~/tmp/cidr-release/notes-X.Y.Z.md`, with this structure:

```markdown
One summary paragraph: what this version is for and its main change.

## Highlights

- User-visible changes, matching CHANGELOG.md.

## Download and update

Download CIDR-Atlas-X.Y.Z.dmg (or CIDR-Atlas.dmg, identical) and its .sha256,
verify the checksum, and drag the app to Applications. Upgrades keep the local
inventory; keep a JSON backup before upgrading. The app is ad hoc signed and not
notarized: after the first open attempt, use System Settings > Privacy &
Security > Open Anyway (https://support.apple.com/en-lamr/102445).

## Verification

- Tests: per-package counts, analyzers and formatting.
- Toolchain: macOS, Xcode, Flutter and Dart versions.
- Architectures: universal app, arm64 and x86_64 verified; CLI built for ...
- Signature: ad hoc, deep/strict verification passed; not notarized.
- Checksum: SHA-256 of CIDR-Atlas-X.Y.Z.dmg.
- Checks not performed.

Source: <full commit SHA>, tagged vX.Y.Z
```

Create the release from the pushed tag with all three assets:

```sh
gh release create vX.Y.Z \
  build/releases/CIDR-Atlas-X.Y.Z.dmg \
  build/releases/CIDR-Atlas-X.Y.Z.dmg.sha256 \
  build/releases/CIDR-Atlas.dmg \
  --repo sergio-farfan/cidr-atlas \
  --verify-tag \
  --title "CIDR Atlas X.Y.Z" \
  --notes-file ~/tmp/cidr-release/notes-X.Y.Z.md
```

For a prerelease add `--prerelease`; it will not become the latest release, and
the stable download link keeps pointing at the previous regular release.
`--verify-tag` stops if the tag is not on the remote.

## 7. Verify the published release

Compare the uploaded asset sizes and digests with the local files:

```sh
gh release view vX.Y.Z --repo sergio-farfan/cidr-atlas \
  --json name,tagName,isPrerelease,assets \
  --jq '.name, .tagName, .isPrerelease, (.assets[] | [.name, .size, .digest] | @tsv)'
stat -f '%N %z' build/releases/CIDR-Atlas-X.Y.Z.dmg* build/releases/CIDR-Atlas.dmg
shasum -a 256 build/releases/CIDR-Atlas-X.Y.Z.dmg* build/releases/CIDR-Atlas.dmg
```

Download the assets into a fresh scratch folder and check them:

```sh
mkdir -p ~/tmp/cidr-release/vX.Y.Z-download
gh release download vX.Y.Z --repo sergio-farfan/cidr-atlas \
  --dir ~/tmp/cidr-release/vX.Y.Z-download
cd ~/tmp/cidr-release/vX.Y.Z-download
shasum -a 256 -c CIDR-Atlas-X.Y.Z.dmg.sha256
cmp CIDR-Atlas-X.Y.Z.dmg CIDR-Atlas.dmg
shasum -a 256 CIDR-Atlas-X.Y.Z.dmg CIDR-Atlas.dmg
```

All sizes and SHA-256 values must match the local files. For a regular release,
confirm that it is now the latest:

```sh
gh api repos/sergio-farfan/cidr-atlas/releases/latest --jq .tag_name
```

Confirm that `/releases/latest/download/CIDR-Atlas.dmg` downloads without signing
in (`curl -sL -o /dev/null -w '%{http_code} %{size_download}\n' <url>`). Finally, record the source
commit, sizes and digests in `PROJECT.md` and commit that update.
