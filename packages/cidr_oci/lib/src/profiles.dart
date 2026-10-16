// CIDR Atlas — Allowlisted OCI profile metadata and executable resolution.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'models.dart';

String configurationPath(String? requested, Map<String, String> environment) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  final path = requested ??
      environment['OCI_CLI_CONFIG_FILE'] ??
      (home == null ? '' : '$home/.oci/config');
  if (path.trim().isEmpty) {
    throw const OciException('Choose an existing OCI configuration file.');
  }
  if (path.startsWith('~/') && home != null) {
    return '$home/${path.substring(2)}';
  }
  return File(path).absolute.path;
}

Future<List<OciProfile>> readProfiles(String path) async {
  final sections = <String, Map<String, String>>{};
  final keys = <String, Set<String>>{};
  String? current;
  // ConfigParser state: the option a deeper-indented line continues, the
  // indent of the last header or option line, and blank lines inside a value.
  String? continuing;
  var indentLevel = 0;
  var pendingBlankLines = 0;
  try {
    await for (final original in File(path)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final line = original.trim();
      if (line.isEmpty) {
        pendingBlankLines++;
        continue;
      }
      if (line.startsWith('#') || line.startsWith(';')) continue;
      final blankLines = pendingBlankLines;
      pendingBlankLines = 0;
      final indent = original.length - original.trimLeft().length;
      if (continuing != null && indent > indentLevel) {
        // Continuations extend the previous value, as ConfigParser does.
        // Only retained metadata keeps the text; credentials are never stored.
        final value = sections[current]![continuing];
        if (continuing == 'security_token_file') {
          sections[current]![continuing] = 'present';
        } else if (value != null) {
          sections[current]![continuing] = '$value${'\n' * blankLines}\n$line';
        }
        continue;
      }
      indentLevel = indent;
      // ConfigParser matches `[` + greedy header + `]` and ignores the rest.
      final header = _sectionHeader.firstMatch(line);
      if (header != null) {
        final name = header.group(1)!;
        if (sections.containsKey(name)) throw const FormatException();
        sections[name] = {};
        keys[name] = {};
        current = name;
        continuing = null;
        continue;
      }
      final separator = line.indexOf(RegExp('[=:]'));
      if (current == null || separator < 1) throw const FormatException();
      final key = line.substring(0, separator).trim().toLowerCase();
      if (!keys[current]!.add(key)) throw const FormatException();
      continuing = key;
      // Secret values and credential paths are never retained in metadata.
      if (key == 'tenancy' || key == 'region') {
        sections[current]![key] = line.substring(separator + 1).trim();
      } else if (key == 'security_token_file') {
        sections[current]![key] =
            line.substring(separator + 1).trim().isEmpty ? '' : 'present';
      }
    }
    if (sections.isEmpty) throw const FormatException();
  } on FileSystemException {
    throw const OciException(
        'Cannot read the OCI configuration file. Choose an existing readable configuration.');
  } on FormatException {
    throw const OciException(
        'Malformed OCI configuration. Repair its profile sections and key/value entries.');
  }
  final defaults = sections['DEFAULT'] ?? const <String, String>{};
  return List.unmodifiable(sections.entries.map((section) {
    final metadata = {...defaults, ...section.value};
    return OciProfile(
        name: section.key,
        tenancyId: metadata['tenancy'] ?? '',
        region: metadata['region'] ?? '',
        authMode: (metadata['security_token_file'] ?? '').isEmpty
            ? OciAuthMode.apiKey
            : OciAuthMode.securityToken);
  }));
}

final _sectionHeader = RegExp(r'^\[(.+)\]');

Future<String> findExecutable(String? override, Map<String, String> environment,
    List<String> standardCandidates) async {
  Future<bool> executableFile(String path) async {
    try {
      final stat = await File(path).stat();
      return stat.type == FileSystemEntityType.file &&
          (Platform.isWindows || (stat.mode & 0x49) != 0);
    } on FileSystemException {
      return false;
    }
  }

  if (override != null) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    final candidate = override.startsWith('~/') && home != null
        ? File('$home/${override.substring(2)}').absolute.path
        : File(override).absolute.path;
    if (await executableFile(candidate)) return candidate;
    throw const OciException(
        'The selected OCI executable is missing or not executable. Choose an installed OCI CLI.');
  }
  final delimiter = Platform.isWindows ? ';' : ':';
  for (final directory in (environment['PATH'] ?? '').split(delimiter)) {
    if (directory.isEmpty) continue;
    final name = Platform.isWindows ? 'oci.exe' : 'oci';
    final candidate = File('$directory/$name').absolute.path;
    if (await executableFile(candidate)) return candidate;
  }
  for (final candidate in standardCandidates) {
    if (await executableFile(candidate)) return candidate;
  }
  throw const OciException(
      'OCI CLI was not found. Install it using Oracle instructions or choose an executable path.');
}
