#!/usr/bin/env bash
# CIDR Atlas
# Launch the macOS application from Finder or Terminal.
# Author: Sergio Farfan <sergio.farfan@gmail.com>

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "CIDR Atlas for macOS must be launched on a Mac with Xcode and Flutter." >&2
  exit 1
fi

flutter_executable="${FLUTTER_BIN:-}"
if [[ -z "$flutter_executable" ]]; then
  flutter_executable="$(command -v flutter || true)"
fi
if [[ -z "$flutter_executable" && -x "$HOME/development/flutter/bin/flutter" ]]; then
  flutter_executable="$HOME/development/flutter/bin/flutter"
fi
if [[ -z "$flutter_executable" && -x "$HOME/flutter/bin/flutter" ]]; then
  flutter_executable="$HOME/flutter/bin/flutter"
fi
if [[ -z "$flutter_executable" || ! -x "$flutter_executable" ]]; then
  echo "Flutter was not found. Install Flutter, add it to PATH, or set FLUTTER_BIN." >&2
  echo "Then run flutter doctor -v to check the macOS toolchain." >&2
  exit 1
fi

cd "$project_root/apps/cidr_atlas"
"$flutter_executable" pub get
exec "$flutter_executable" run -d macos "$@"
