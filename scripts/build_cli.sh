#!/usr/bin/env bash
# CIDR Atlas
# Build the standalone command-line executable.
# Author: Sergio Farfan <sergio.farfan@gmail.com>

set -euo pipefail

usage() {
  echo "Usage: $0 [--both]" >&2
  echo "  (no option)  build build/cidrctl for the current operating system" >&2
  echo "  --both       macOS only: build build/cidrctl-arm64 and build/cidrctl-x86_64" >&2
}

both=false
if [[ $# -eq 1 && "$1" == "--both" ]]; then
  both=true
elif [[ $# -ne 0 ]]; then
  usage
  exit 2
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_executable="${DART_BIN:-$(command -v dart || true)}"
if [[ -z "$dart_executable" || ! -x "$dart_executable" ]]; then
  echo "Dart was not found. Add the Flutter/Dart SDK to PATH or set DART_BIN." >&2
  exit 1
fi

cd "$project_root/packages/cidr_cli"
"$dart_executable" pub get
mkdir -p "$project_root/build"

if [[ "$both" == false ]]; then
  output_path="$project_root/build/cidrctl"
  if [[ "${OS:-}" == "Windows_NT" ]]; then
    output_path="$output_path.exe"
  fi
  "$dart_executable" compile exe bin/cidrctl.dart -o "$output_path"
  echo "Built CLI for the current operating system: $output_path"
  exit 0
fi

# Release packaging needs one executable per Mac architecture. `dart compile
# exe` cannot cross-compile to macOS x64, and `lipo -create` breaks a Dart AOT
# executable (the appended snapshot is lost), so there is no universal cidrctl:
# the x86_64 build runs an x64 Dart SDK of the same version under Rosetta.
if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "--both requires an Apple silicon Mac with Rosetta." >&2
  exit 1
fi
dart_x64="${DART_X64_BIN:-}"
if [[ -z "$dart_x64" || ! -x "$dart_x64" ]]; then
  echo "Set DART_X64_BIN to the dart executable of an x64 macOS Dart SDK with" >&2
  echo "the same version as $dart_executable. This script does not install SDKs." >&2
  exit 1
fi
if ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "Rosetta is required to run the x64 Dart SDK." >&2
  exit 1
fi
arm_version="$("$dart_executable" --version 2>&1)"
x64_version="$(/usr/bin/arch -x86_64 "$dart_x64" --version 2>&1)"
if [[ "$arm_version" != *macos_arm64* ]]; then
  echo "DART_BIN is not an arm64 macOS Dart SDK: $arm_version" >&2
  exit 1
fi
if [[ "$x64_version" != *macos_x64* ]]; then
  echo "DART_X64_BIN is not an x64 macOS Dart SDK: $x64_version" >&2
  exit 1
fi
version_of() { sed -E 's/^Dart SDK version: ([^ ]+).*/\1/' <<<"$1"; }
if [[ "$(version_of "$arm_version")" != "$(version_of "$x64_version")" ]]; then
  echo "Dart SDK versions differ: arm64 $(version_of "$arm_version"), x64 $(version_of "$x64_version")." >&2
  exit 1
fi

arm_output="$project_root/build/cidrctl-arm64"
x64_output="$project_root/build/cidrctl-x86_64"
"$dart_executable" compile exe bin/cidrctl.dart -o "$arm_output"
/usr/bin/arch -x86_64 "$dart_x64" compile exe bin/cidrctl.dart -o "$x64_output"

expected="$(sed -nE 's/^version: ([^ ]+).*/\1/p' pubspec.yaml)"
check() {
  local path="$1" architecture="$2" reported
  test "$(/usr/bin/lipo -archs "$path")" = "$architecture"
  /usr/bin/codesign --verify --strict "$path"
  reported="$(/usr/bin/arch "-$architecture" "$path" --version)"
  if [[ "$reported" != "cidrctl $expected" ]]; then
    echo "$path reports '$reported', expected 'cidrctl $expected'." >&2
    exit 1
  fi
}
check "$arm_output" arm64
check "$x64_output" x86_64
echo "Built cidrctl $expected for both Mac architectures:"
echo "  $arm_output"
echo "  $x64_output"
