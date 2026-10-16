#!/usr/bin/env bash
# CIDR Atlas
# Build the standalone command-line executable.
# Author: Sergio Farfan <sergio.farfan@gmail.com>

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_executable="${DART_BIN:-$(command -v dart || true)}"
if [[ -z "$dart_executable" || ! -x "$dart_executable" ]]; then
  echo "Dart was not found. Add the Flutter/Dart SDK to PATH or set DART_BIN." >&2
  exit 1
fi

cd "$project_root/packages/cidr_cli"
"$dart_executable" pub get
mkdir -p "$project_root/build"
output_path="$project_root/build/cidrctl"
if [[ "${OS:-}" == "Windows_NT" ]]; then
  output_path="$output_path.exe"
fi
"$dart_executable" compile exe bin/cidrctl.dart -o "$output_path"
echo "Built CLI for the current operating system: $output_path"
