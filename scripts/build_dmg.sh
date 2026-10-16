#!/usr/bin/env bash
# CIDR Atlas
# Build and verify a macOS disk image and its SHA-256 checksum.
# Author: Sergio Farfan <sergio.farfan@gmail.com>

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Creating a DMG requires macOS with Apple's disk image tools." >&2
  exit 1
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--skip-build" ) ]]; then
  echo "Usage: $0 [--skip-build]" >&2
  exit 2
fi
if [[ $# -eq 0 ]]; then
  "$project_root/scripts/build_macos.sh"
fi

app_path="$project_root/apps/cidr_atlas/build/macos/Build/Products/Release/CIDR Atlas.app"
if [[ ! -d "$app_path" ]]; then
  echo "Release application missing. Run scripts/build_macos.sh first." >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "The application version is not suitable for a release filename." >&2
  exit 1
fi
for architecture in arm64 x86_64; do
  /usr/bin/lipo "$app_path/Contents/MacOS/CIDR Atlas" -verify_arch "$architecture"
done
/usr/bin/codesign --verify --deep --strict "$app_path"

release_dir="$project_root/build/releases"
mkdir -p "$release_dir"
asset_name="CIDR-Atlas-$version.dmg"
# Stable-name copy for the releases/latest/download link; identical bytes.
stable_name="CIDR-Atlas.dmg"
image_path="$release_dir/$asset_name"
staging_dir="$(mktemp -d "$project_root/build/cidr-atlas-dmg.XXXXXX")"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then
    /usr/bin/hdiutil detach "$staging_dir/mounted" >/dev/null || true
  fi
  rm -rf "$staging_dir"
}
trap cleanup EXIT
mkdir "$staging_dir/content" "$staging_dir/mounted"
/usr/bin/ditto "$app_path" "$staging_dir/content/CIDR Atlas.app"
ln -s /Applications "$staging_dir/content/Applications"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$staging_dir/content/THIRD_PARTY_NOTICES.md"
cp "$project_root/third_party/FLUTTER_LICENSE" "$staging_dir/content/FLUTTER_LICENSE"
cat > "$staging_dir/content/INSTALL.txt" <<'INSTALL'
CIDR Atlas
Author: Sergio Farfan <sergio.farfan@gmail.com>

Drag CIDR Atlas.app to Applications, then eject this disk image.
New installations start with an empty inventory. Upgrades retain local records.
Offline CSV/JSON imports are available from Import. Live OCI discovery requires
an existing OCI CLI installation and profile, plus explicit scope selection.

This preview release uses an ad hoc signature. It has no Developer ID signature
or Apple notarization ticket; macOS may require explicit approval to open it.
INSTALL

/usr/bin/hdiutil create -srcfolder "$staging_dir/content" \
  -volname "CIDR Atlas $version" -fs HFS+ -format UDZO -ov "$image_path"
/usr/bin/hdiutil verify "$image_path"
/usr/bin/hdiutil attach "$image_path" -readonly -nobrowse -noautoopen \
  -mountpoint "$staging_dir/mounted" >/dev/null
mounted=true
mounted_app="$staging_dir/mounted/CIDR Atlas.app"
test -d "$mounted_app"
test "$(readlink "$staging_dir/mounted/Applications")" = /Applications
test -s "$staging_dir/mounted/INSTALL.txt"
test -s "$staging_dir/mounted/THIRD_PARTY_NOTICES.md"
test -s "$staging_dir/mounted/FLUTTER_LICENSE"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mounted_app/Contents/Info.plist")" = "$version"
for architecture in arm64 x86_64; do
  /usr/bin/lipo "$mounted_app/Contents/MacOS/CIDR Atlas" -verify_arch "$architecture"
done
/usr/bin/codesign --verify --deep --strict "$mounted_app"
/usr/bin/hdiutil detach "$staging_dir/mounted"
mounted=false
(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "$asset_name" > "$asset_name.sha256"
  /usr/bin/shasum -a 256 -c "$asset_name.sha256"
  /bin/cp -f "$asset_name" "$stable_name"
  /usr/bin/cmp "$asset_name" "$stable_name"
)
echo "Verified disk image: $image_path"
echo "SHA-256 checksum: $image_path.sha256"
echo "Stable-name copy: $release_dir/$stable_name"
