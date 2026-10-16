#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "A macOS release build requires a Mac with Xcode and Flutter." >&2
  exit 1
fi
flutter_executable="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "$flutter_executable" || ! -x "$flutter_executable" ]]; then
  echo "Add Flutter to PATH or set FLUTTER_BIN to its executable." >&2
  exit 1
fi

cd "$project_root/apps/cidr_atlas"
"$flutter_executable" pub get
"$flutter_executable" build macos --release "$@"
echo "Release application: $project_root/apps/cidr_atlas/build/macos/Build/Products/Release/"
