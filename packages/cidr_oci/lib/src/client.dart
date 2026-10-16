// CIDR Atlas — Scoped OCI CLI inventory collection and metadata selection.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'commands.dart';
import 'models.dart';
import 'profiles.dart';
import 'process_runner.dart';

abstract interface class OciInventoryClient {
  Future<List<OciProfile>> profiles({String? configFile});
  Future<OciConnection> connection(
      {required String profile,
      String? configFile,
      String? executable,
      OciAuthMode? authMode});
  Future<List<OciRegion>> regions(OciConnection connection,
      {OciCancellation? cancellation});
  Future<List<OciCompartment>> compartments(OciConnection connection,
      {required String region, OciCancellation? cancellation});
  Future<OciDiscovery> discover(OciConnection connection,
      {required String region,
      required String compartmentId,
      OciCancellation? cancellation,
      void Function(String)? onProgress});
}

class OciCliClient implements OciInventoryClient {
  OciCliClient(
      {OciCommandRunner? runner,
      Map<String, String>? environment,
      DateTime Function()? clock,
      Duration commandTimeout = const Duration(seconds: 60),
      Duration collectionTimeout = const Duration(seconds: 180),
      List<String>? executableCandidates})
      : _environment = Map.unmodifiable(environment ?? Platform.environment),
        _candidates = executableCandidates ??
            const ['/opt/homebrew/bin/oci', '/usr/local/bin/oci'],
        _clock = clock ?? DateTime.now,
        _collectionTimeout = collectionTimeout,
        _commands = OciCommands(
            runner: runner ?? const OciProcessRunner().run,
            environment: environment ?? Platform.environment,
            timeout: commandTimeout);

  final Map<String, String> _environment;
  final List<String> _candidates;
  final DateTime Function() _clock;
  final Duration _collectionTimeout;
  final OciCommands _commands;

  @override
  Future<List<OciProfile>> profiles({String? configFile}) =>
      readProfiles(configurationPath(configFile, _environment));
  @override
  Future<OciConnection> connection(
      {required String profile,
      String? configFile,
      String? executable,
      OciAuthMode? authMode}) async {
    final path = configurationPath(configFile, _environment);
    final available = await readProfiles(path);
    final selected =
        available.where((entry) => entry.name == profile).firstOrNull;
    if (selected == null)
      throw const OciException(
          'The selected profile is absent from the OCI configuration.');
    if (selected.tenancyId.trim().isEmpty)
      throw const OciException(
          'The OCI profile needs a tenancy identifier. Repair its configuration.');
    return OciConnection(
        executable: await findExecutable(executable, _environment, _candidates),
        configFile: path,
        profile: selected.name,
        tenancyId: selected.tenancyId,
        authMode: authMode ?? selected.authMode);
  }

  @override
  Future<List<OciRegion>> regions(OciConnection connection,
      {OciCancellation? cancellation}) async {
    checkCancellation(cancellation);
    final available = await profiles(configFile: connection.configFile);
    final selected = available
        .where((entry) => entry.name == connection.profile)
        .firstOrNull;
    if (selected == null || selected.region.trim().isEmpty) {
      throw const OciException(
          'The selected profile needs a default region to list subscriptions. Set its region or enter scopes manually.');
    }
    final response = await _commands.request(
        connection,
        selected.region,
        [
          'iam',
          'region-subscription',
          'list',
          '--tenancy-id',
          connection.tenancyId,
          '--all'
        ],
        cancellation: cancellation);
    return List.unmodifiable(responseList(response).map((entry) {
      final isHome = entry['is-home-region'];
      if (isHome != null && isHome is! bool) throw malformedResponse();
      return OciRegion(
          name: requiredString(entry, 'region-name'),
          status: requiredString(entry, 'status'),
          isHome: isHome == true);
    }));
  }

  @override
  Future<List<OciCompartment>> compartments(OciConnection connection,
      {required String region, OciCancellation? cancellation}) async {
    final response = await _commands.request(
        connection,
        region,
        [
          'iam',
          'compartment',
          'list',
          '--compartment-id',
          connection.tenancyId,
          '--compartment-id-in-subtree',
          'true',
          '--access-level',
          'ACCESSIBLE',
          '--lifecycle-state',
          'ACTIVE',
          '--all'
        ],
        cancellation: cancellation);
    final scopes = <String, OciCompartment>{
      connection.tenancyId: OciCompartment(
          id: connection.tenancyId,
          name: 'Tenancy root (${connection.tenancyId})')
    };
    for (final entry in responseList(response)) {
      final id = requiredString(entry, 'id');
      final name = requiredString(entry, 'name');
      scopes.putIfAbsent(id, () => OciCompartment(id: id, name: name));
    }
    return List.unmodifiable(scopes.values);
  }

  @override
  Future<OciDiscovery> discover(OciConnection connection,
      {required String region,
      required String compartmentId,
      OciCancellation? cancellation,
      void Function(String)? onProgress}) async {
    checkCancellation(cancellation);
    if (region.trim().isEmpty || compartmentId.trim().isEmpty) {
      throw const OciException(
          'Select a region and compartment before discovery.');
    }
    final started = _clock().toUtc();
    final scopedCancellation = OciCancellation();
    cancellation?.whenCancelled.then((_) => scopedCancellation.cancel());
    var expired = false;
    final deadline = Timer(_collectionTimeout, () {
      expired = true;
      scopedCancellation.cancel();
    });
    final warnings = <String>[];
    final contextSuccesses = <String>[];
    final contextFailures = <String>[];
    try {
      onProgress?.call('Loading selected-compartment VCNs');
      final vcns = responseList(await _commands.request(
          connection,
          region,
          [
            'network',
            'vcn',
            'list',
            '--compartment-id',
            compartmentId,
            '--all'
          ],
          cancellation: scopedCancellation));
      _validateResources(vcns, compartmentId: compartmentId);
      onProgress?.call('Loading selected-compartment subnets');
      final subnets = responseList(await _commands.request(
          connection,
          region,
          [
            'network',
            'subnet',
            'list',
            '--compartment-id',
            compartmentId,
            '--all'
          ],
          cancellation: scopedCancellation));
      _validateResources(subnets, compartmentId: compartmentId, subnets: true);
      final known = vcns.map((entry) => entry['id'] as String).toSet();
      final missing = subnets
          .map((entry) => entry['vcn-id'] as String)
          .where((id) => !known.contains(id))
          .toSet();
      for (final id in missing) {
        checkCancellation(scopedCancellation);
        onProgress?.call('Loading referenced VCN context');
        try {
          final context = responseObject(await _commands.request(
              connection, region, ['network', 'vcn', 'get', '--vcn-id', id],
              cancellation: scopedCancellation));
          _validateResources([context]);
          if (context['id'] != id) throw malformedResponse();
          vcns.add(context);
          contextSuccesses.add(id);
          final contextCompartment = context['compartment-id'];
          warnings.add(
              'Referenced VCN $id was included as context from compartment $contextCompartment; its other subnets were not collected.');
        } on OciCommandFailure catch (error) {
          if (!error.unavailableContext) rethrow;
          contextFailures.add(id);
          warnings.add(
              'Referenced VCN $id is unavailable or access was denied. Its subnet references remain; this does not prove deletion.');
        }
      }
      checkCancellation(scopedCancellation);
      final completed = _clock().toUtc();
      final coverage =
          'Scoped observation in region $region, compartment $compartmentId, '
          'collecting all pages of directly contained VCNs and subnets only (no descendant resource traversal). '
          'Observation interval ${started.toIso8601String()} to ${completed.toIso8601String()}. '
          'Referenced VCN context included: ${contextSuccesses.isEmpty ? "none" : contextSuccesses.join(", ")}; '
          'unavailable context: ${contextFailures.isEmpty ? "none" : contextFailures.join(", ")}. '
          '${warnings.join(" ")} This is not a transactionally consistent snapshot and not a complete tenancy audit. '
          'Omitted resources are not evidence of deletion or free address space.';
      return OciDiscovery(
          bundleJson: jsonEncode({
            'metadata': {
              'tenancy': connection.tenancyId,
              'region': region,
              'collectionStartedAt': started.toIso8601String(),
              'collectedAt': completed.toIso8601String(),
              'coverage': coverage
            },
            'vcns': vcns,
            'subnets': subnets,
          }),
          warnings: List.unmodifiable(warnings));
    } on OciException {
      if (expired)
        throw const OciException(
            'OCI collection timed out. Retry the selected scope or check connectivity.');
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  void _validateResources(List<Map<String, dynamic>> resources,
      {String? compartmentId, bool subnets = false}) {
    final ids = <String>{};
    for (final resource in resources) {
      if (!ids.add(requiredString(resource, 'id'))) throw malformedResponse();
      final actualCompartment = requiredString(resource, 'compartment-id');
      if (compartmentId != null && actualCompartment != compartmentId)
        throw malformedResponse();
      if (subnets) requiredString(resource, 'vcn-id');
    }
  }
}
