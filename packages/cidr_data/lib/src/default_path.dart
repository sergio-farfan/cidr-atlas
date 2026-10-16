// CIDR Atlas
// Default inventory database location shared by the CLI and the application.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

/// The default inventory database path for [operatingSystem], using the
/// values in [environment] only.
///
/// [operatingSystem] uses [Platform.operatingSystem] names and defaults to
/// the current platform, so every layout can be tested from one host:
///
/// - `macos`: `$HOME/Library/Application Support/cidr_atlas/inventory.sqlite`
///   (falling back to `USERPROFILE` when `HOME` is unset).
/// - `windows`: `%APPDATA%/cidr_atlas/inventory.sqlite`.
/// - any other system: `$XDG_DATA_HOME/cidr_atlas/inventory.sqlite` when
///   `XDG_DATA_HOME` is an absolute path, otherwise
///   `$HOME/.local/share/cidr_atlas/inventory.sqlite`. The XDG Base Directory
///   specification says relative values are invalid and must be ignored.
///
/// Throws a [StateError] when the required variable is not set.
String defaultDatabasePath(
  Map<String, String> environment, {
  String? operatingSystem,
}) {
  final system = operatingSystem ?? Platform.operatingSystem;
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  if (system == 'macos') {
    if (home == null) throw StateError('HOME is not set; specify --db.');
    return '$home/Library/Application Support/cidr_atlas/inventory.sqlite';
  }
  if (system == 'windows') {
    final appData = environment['APPDATA'];
    if (appData == null) throw StateError('APPDATA is not set; specify --db.');
    return '$appData/cidr_atlas/inventory.sqlite';
  }
  final dataHome = environment['XDG_DATA_HOME'];
  if (dataHome != null && dataHome.startsWith('/')) {
    return '$dataHome/cidr_atlas/inventory.sqlite';
  }
  if (home == null) throw StateError('HOME is not set; specify --db.');
  return '$home/.local/share/cidr_atlas/inventory.sqlite';
}
