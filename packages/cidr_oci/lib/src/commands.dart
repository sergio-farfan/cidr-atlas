// CIDR Atlas — Explicit OCI requests, isolated environment and safe errors.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'process_runner.dart';

class OciCommands {
  OciCommands(
      {required this.runner, required this.environment, required this.timeout});
  final OciCommandRunner runner;
  final Map<String, String> environment;
  final Duration timeout;

  Future<Object?> request(
      OciConnection connection, String region, List<String> suffix,
      {OciCancellation? cancellation,
      required String step,
      bool listResponse = false}) async {
    checkCancellation(cancellation);
    if ([
      connection.executable,
      connection.configFile,
      connection.profile,
      connection.tenancyId,
      region
    ].any((value) => value.trim().isEmpty)) {
      throw const OciException(
          'Choose an OCI executable, configuration, profile, tenancy and region before loading resources.');
    }
    final Directory temporary;
    try {
      temporary = await Directory.systemTemp.createTemp('cidr-atlas-oci-');
      await File('${temporary.path}/empty_rc').writeAsString('');
    } on FileSystemException {
      throw const OciException(
          'Cannot create temporary OCI request settings. Check access to the local temporary directory.');
    }
    final local = OciCancellation();
    var expired = false;
    final timer = Timer(timeout, () {
      expired = true;
      local.cancel();
    });
    cancellation?.whenCancelled.then((_) => local.cancel());
    final safeEnvironment = <String, String>{
      for (final entry in environment.entries)
        if (!entry.key.toUpperCase().startsWith('OCI_') ||
            entry.key == 'OCI_CLI_CERT_BUNDLE')
          entry.key: entry.value,
    };
    Future<OciCommandResult>? running;
    try {
      checkCancellation(cancellation);
      running = runner(OciCommand(
          executable: connection.executable,
          arguments: List.unmodifiable([
            '--config-file',
            connection.configFile,
            '--profile',
            connection.profile,
            '--auth',
            connection.authMode == OciAuthMode.securityToken
                ? 'security_token'
                : 'api_key',
            '--region',
            region,
            '--output',
            'json',
            '--cli-rc-file',
            '${temporary.path}/empty_rc',
            '--connection-timeout',
            '10',
            '--read-timeout',
            '60',
            '--max-retries',
            '1',
            ...suffix,
          ]),
          environment: Map.unmodifiable(safeEnvironment),
          timeout: timeout,
          cancellation: local));
      final response = await Future.any<Object>([
        running,
        local.whenCancelled.then((_) => OciException(expired
            ? 'OCI request timed out. Check connectivity or retry a smaller scope.'
            : 'OCI request cancelled.')),
      ]);
      if (response is OciException) throw response;
      checkCancellation(cancellation);
      if (local.isCancelled) throw const OciException('OCI request timed out.');
      final result = response as OciCommandResult;
      if (result.exitCode != 0) throw _failure(result);
      if (result.stdout.trim().isEmpty) {
        // OCI CLI omits output for successful empty lists. Object lookups
        // still require their JSON envelope and must never become empty lists.
        if (listResponse) return <Object?>[];
        throw malformedResponse(
            step, 'expected a JSON object, but CLI output was empty');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(result.stdout);
      } on FormatException {
        throw malformedResponse(step, 'CLI output was not valid JSON');
      }
      if (decoded is! Map<String, dynamic>)
        throw malformedResponse(step, 'expected a JSON object envelope');
      if (!decoded.containsKey('data'))
        throw malformedResponse(step, 'required field "data" was missing');
      return decoded['data'];
    } catch (error) {
      local.cancel();
      if (running != null) {
        try {
          await running.timeout(const Duration(seconds: 2));
        } catch (_) {/* Bound cleanup without exposing command output. */}
      }
      if (error is OciException) rethrow;
      throw const OciException(
          'OCI request failed. Check the CLI installation, profile and selected scope.');
    } finally {
      timer.cancel();
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        /* No credentials or inventory are stored here. */
      }
    }
  }

  OciCommandFailure _failure(OciCommandResult result) {
    final expiredSession = [
      result.stderr,
      result.stdout
    ].any((output) => const LineSplitter().convert(output).any((line) =>
        line.trim() ==
        'ERROR: This CLI session has expired, so it cannot currently be used to run commands'));
    String? code;
    for (final output in [result.stderr, result.stdout]) {
      final begin = output.indexOf('{');
      final end = output.lastIndexOf('}');
      if (begin < 0 || end < begin) continue;
      try {
        final decoded = jsonDecode(output.substring(begin, end + 1));
        if (decoded is Map && decoded['code'] is String)
          code = decoded['code'] as String;
      } on FormatException {/* Never expose unstructured CLI errors. */}
    }
    final authFailure = const {
          'NotAuthenticated',
          'InvalidAuthenticationInfo',
          'InvalidAuthenticationToken',
          'ExpiredAuthenticationToken'
        }.contains(code) ||
        expiredSession;
    return OciCommandFailure(
        authFailure
            ? 'OCI authentication failed. Repair the selected CLI profile credentials or renew its session, then retry.'
            : 'OCI request failed. Check the CLI profile, IAM permissions, connectivity and selected scope.',
        unavailableContext: const {
          'NotAuthorizedOrNotFound',
          'NotFound',
          'NotAuthorized'
        }.contains(code));
  }
}

class OciCommandFailure extends OciException {
  const OciCommandFailure(super.message, {required this.unavailableContext});
  final bool unavailableContext;
}

void checkCancellation(OciCancellation? cancellation) {
  if (cancellation?.isCancelled ?? false)
    throw const OciException('OCI request cancelled.');
}

OciException malformedResponse(String step, String detail) => OciException(
    'Malformed OCI response during $step: $detail. Check the CLI version and retry the selected scope.');

String requiredString(Map<String, dynamic> object, String key,
    {required String step}) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty)
    throw malformedResponse(
        step, 'required field "$key" must be a nonempty string');
  return value;
}

Map<String, dynamic> responseObject(Object? value, {required String step}) {
  if (value is! Map<String, dynamic>)
    throw malformedResponse(step, 'expected an object in "data"');
  return value;
}

List<Map<String, dynamic>> responseList(Object? value, {required String step}) {
  if (value is! List)
    throw malformedResponse(step, 'expected a list in "data"');
  return value.map((entry) => responseObject(entry, step: step)).toList();
}
