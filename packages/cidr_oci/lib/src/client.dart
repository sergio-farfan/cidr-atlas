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

  /// Collects VCNs and subnets for the selected scope. [onProgress] receives
  /// each progress line; [onDiscoveryProgress] receives the same line with
  /// the scope count and the collection time limit in effect.
  Future<OciDiscovery> discover(OciConnection connection,
      {List<String> regions = const [],
      bool allRegions = false,
      String? compartmentId,
      bool allCompartments = false,
      OciCancellation? cancellation,
      void Function(String)? onProgress,
      void Function(OciDiscoveryProgress)? onDiscoveryProgress});
}

class OciCliClient implements OciInventoryClient {
  OciCliClient(
      {OciCommandRunner? runner,
      Map<String, String>? environment,
      DateTime Function()? clock,
      Duration commandTimeout = const Duration(seconds: 120),
      Duration? collectionTimeout,
      List<String>? executableCandidates})
      : _environment = Map.unmodifiable(environment ?? Platform.environment),
        _candidates = executableCandidates ??
            _defaultCandidates(environment ?? Platform.environment),
        _clock = clock ?? DateTime.now,
        _collectionTimeout = collectionTimeout,
        _commands = OciCommands(
            runner: runner ?? const OciProcessRunner().run,
            environment: environment ?? Platform.environment,
            timeout: commandTimeout);

  final Map<String, String> _environment;
  final List<String> _candidates;
  final DateTime Function() _clock;
  final Duration? _collectionTimeout;
  final OciCommands _commands;

  /// Oracle's installer defaults to `$HOME/bin`; Homebrew uses the others.
  /// The home directory lookup matches the `~/` expansion of an explicit
  /// executable path.
  static List<String> _defaultCandidates(Map<String, String> environment) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    return [
      if (home != null && home.trim().isNotEmpty) '$home/bin/oci',
      '/opt/homebrew/bin/oci',
      '/usr/local/bin/oci'
    ];
  }

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
    if (selected == null) {
      throw const OciException(
          'The selected profile is absent from the OCI configuration.');
    }
    if (selected.tenancyId.trim().isEmpty) {
      throw const OciException(
          'The OCI profile needs a tenancy identifier. Repair its configuration.');
    }
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
        cancellation: cancellation,
        step: 'region subscription list',
        listResponse: true);
    return List.unmodifiable(
        responseList(response, step: 'region subscription list').map((entry) {
      final isHome = entry['is-home-region'];
      if (isHome != null && isHome is! bool) {
        throw malformedResponse('region subscription list',
            'field "is-home-region" must be a boolean');
      }
      final key = entry['region-key'];
      if (key != null && key is! String) {
        throw malformedResponse(
            'region subscription list', 'field "region-key" must be a string');
      }
      return OciRegion(
          name: requiredString(entry, 'region-name',
              step: 'region subscription list'),
          status:
              requiredString(entry, 'status', step: 'region subscription list'),
          isHome: isHome == true,
          key: key is String && key.trim().isNotEmpty ? key.trim() : null);
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
        cancellation: cancellation,
        step: 'compartment list',
        listResponse: true);
    final listed = <String, ({String name, String? parentId})>{};
    for (final entry in responseList(response, step: 'compartment list')) {
      final id = requiredString(entry, 'id', step: 'compartment list');
      if (id == connection.tenancyId) continue;
      // Restricted entries may omit display fields; only the id is required.
      final name = entry['name'];
      final parent = entry['compartment-id'];
      listed.putIfAbsent(
          id,
          () => (
                name: name is String && name.trim().isNotEmpty ? name : id,
                parentId:
                    parent is String && parent.trim().isNotEmpty ? parent : null
              ));
    }
    String pathOf(String id) {
      final segments = <String>[];
      final visited = <String>{};
      String? current = id;
      while (current != null && visited.add(current)) {
        if (current == connection.tenancyId) {
          return [_rootSegment, ...segments.reversed].join(' / ');
        }
        final entry = listed[current];
        if (entry == null) break;
        segments.add(entry.name);
        current = entry.parentId;
      }
      // An unlisted ancestor or a malformed parent cycle: display only.
      return ['…', ...segments.reversed].join(' / ');
    }

    final children = [
      for (final MapEntry(key: id, value: entry) in listed.entries)
        OciCompartment(
            id: id,
            name: entry.name,
            parentId: entry.parentId,
            path: pathOf(id))
    ]..sort((a, b) {
        final folded = a.path!.toLowerCase().compareTo(b.path!.toLowerCase());
        if (folded != 0) return folded;
        final exact = a.path!.compareTo(b.path!);
        return exact != 0 ? exact : a.id.compareTo(b.id);
      });
    return List.unmodifiable([
      OciCompartment(
          id: connection.tenancyId,
          name: 'Tenancy root (${connection.tenancyId})',
          path: _rootSegment),
      ...children
    ]);
  }

  static const _rootSegment = 'root';
  static final _fullRegion = RegExp(r'^[a-z]+(-[a-z]+)+-[0-9]+$');
  static final _regionKey = RegExp(r'^[a-z]{3}$');

  /// Maps short region keys to region identifiers using the tenancy's region
  /// subscriptions, so aliases never become separate inventory scopes.
  Future<List<String>> _canonicalRegions(
      OciConnection connection, List<String> requested,
      {required OciCancellation cancellation,
      void Function(String)? onProgress}) async {
    final keys = requested.where((region) => !_fullRegion.hasMatch(region));
    if (keys.isEmpty) return requested.toSet().toList();
    onProgress?.call('Resolving region keys from region subscriptions');
    final Map<String, String> names;
    try {
      names = {
        for (final subscription
            in await regions(connection, cancellation: cancellation))
          if (subscription.key != null)
            subscription.key!.toLowerCase():
                subscription.name.trim().toLowerCase()
      };
    } on OciException catch (error) {
      if (cancellation.isCancelled) rethrow;
      throw OciException('Region key "${keys.first}" could not be resolved: '
          '${error.message} Enter the full region identifier instead, for '
          'example us-ashburn-1.');
    }
    final unknown = keys.where((key) => !names.containsKey(key)).toSet();
    if (unknown.isNotEmpty) {
      throw OciException('Region key ${unknown.map((k) => '"$k"').join(", ")} '
          'is not among the tenancy region subscriptions. Enter the full '
          'region identifier, for example us-ashburn-1.');
    }
    return requested.map((region) => names[region] ?? region).toSet().toList();
  }

  @override
  Future<OciDiscovery> discover(OciConnection connection,
      {List<String> regions = const [],
      bool allRegions = false,
      String? compartmentId,
      bool allCompartments = false,
      OciCancellation? cancellation,
      void Function(String)? onProgress,
      void Function(OciDiscoveryProgress)? onDiscoveryProgress}) async {
    checkCancellation(cancellation);
    // OCI region identifiers are lowercase; the CLI also accepts case variants
    // and short keys for the same endpoint, so canonicalize before dedupe.
    final requestedRegions =
        regions.map((region) => region.trim().toLowerCase()).toList();
    final selectedCompartment = compartmentId?.trim();
    if (requestedRegions.any((region) => region.isEmpty) ||
        (allRegions && requestedRegions.isNotEmpty) ||
        (!allRegions && requestedRegions.isEmpty)) {
      throw const OciException(
          'Select one or more regions, or all READY regions, before discovery. These region modes cannot be combined.');
    }
    if ((allCompartments && compartmentId != null) ||
        (!allCompartments &&
            (selectedCompartment == null || selectedCompartment.isEmpty))) {
      throw const OciException(
          'Select one compartment, or all accessible compartments, before discovery. These compartment modes cannot be combined.');
    }
    final malformed = requestedRegions.where((region) =>
        !_fullRegion.hasMatch(region) && !_regionKey.hasMatch(region));
    if (malformed.isNotEmpty) {
      throw OciException('Region "${malformed.first}" is not a full region '
          'identifier such as us-ashburn-1 or a three-letter region key such '
          'as IAD. Enter the full region identifier.');
    }
    final selectedRegions = requestedRegions.toSet().toList();
    final started = _clock().toUtc();
    final scopedCancellation = OciCancellation();
    cancellation?.whenCancelled.then((_) => scopedCancellation.cancel());
    Duration limitFor(List<String> regionScopes) =>
        _collectionTimeout ??
        (allRegions || allCompartments || regionScopes.length > 1
            ? OciCollectionLimits.broadScope
            : OciCollectionLimits.singleScope);
    var expired = false;
    var currentOperation = 'scope enumeration';
    var completedScopes = 0;
    var scopeCount = 0;
    // The deadline covers region key resolution too. Resolution can only
    // merge aliases, so the limit is provisional until then and may narrow.
    var collectionLimit = limitFor(selectedRegions);
    final elapsed = Stopwatch()..start();
    void expire() {
      expired = true;
      scopedCancellation.cancel();
    }

    var deadline = Timer(collectionLimit, expire);
    void report(String message) {
      onProgress?.call(message);
      onDiscoveryProgress?.call(OciDiscoveryProgress(
          message: message,
          collectionTimeout: collectionLimit,
          scopeCount: scopeCount == 0 ? null : scopeCount,
          completedScopes: completedScopes));
    }

    final warnings = <String>[];
    final contextSuccesses = <Map<String, String>>[];
    final contextFailures = <Map<String, String>>[];
    final vcns = <Map<String, dynamic>>[];
    final subnets = <Map<String, dynamic>>[];
    try {
      if (selectedRegions.any((region) => !_fullRegion.hasMatch(region))) {
        currentOperation = 'region key resolution';
        final canonical = await _canonicalRegions(connection, selectedRegions,
            cancellation: scopedCancellation, onProgress: report);
        selectedRegions
          ..clear()
          ..addAll(canonical);
        // ['IAD', 'us-ashburn-1'] is one scope and keeps the single-scope
        // limit, measured from the start of collection.
        final resolvedLimit = limitFor(selectedRegions);
        if (resolvedLimit != collectionLimit) {
          collectionLimit = resolvedLimit;
          deadline.cancel();
          final remaining = resolvedLimit - elapsed.elapsed;
          deadline =
              Timer(remaining.isNegative ? Duration.zero : remaining, expire);
        }
      }
      if (allRegions) {
        currentOperation = 'region subscription list';
        report('Loading READY region subscriptions');
        final List<OciRegion> subscriptions;
        try {
          subscriptions =
              await this.regions(connection, cancellation: scopedCancellation);
        } on OciException catch (error) {
          throw OciException('Region enumeration failed: ${error.message}');
        }
        for (final subscription in subscriptions) {
          if (subscription.status == 'READY') {
            final name = subscription.name.trim().toLowerCase();
            if (!selectedRegions.contains(name)) selectedRegions.add(name);
          } else {
            warnings.add('Region ${subscription.name} was excluded because its '
                'subscription status is ${subscription.status}, not READY.');
          }
        }
        if (selectedRegions.isEmpty) {
          throw const OciException(
              'No READY subscribed regions were returned. Check region subscriptions and IAM visibility, then retry.');
        }
      }
      checkCancellation(scopedCancellation);
      final List<String> compartmentIds;
      if (allCompartments) {
        currentOperation =
            'compartment list in region ${selectedRegions.first}, '
            'tenancy root ${connection.tenancyId}';
        report('Loading accessible active compartments and descendants');
        try {
          final scopes = await compartments(connection,
              region: selectedRegions.first, cancellation: scopedCancellation);
          compartmentIds = scopes.map((scope) => scope.id).toList();
        } on OciException catch (error) {
          throw OciException('$currentOperation failed: ${error.message}');
        }
        warnings.add('All accessible active compartments and the tenancy root '
            'were included. IAM-hidden compartments may not be visible; '
            'compartment visibility does not guarantee permission to list networks.');
      } else {
        compartmentIds = [selectedCompartment!];
      }
      scopeCount = selectedRegions.length * compartmentIds.length;
      for (final region in selectedRegions) {
        final regionalVcns = <String, Map<String, dynamic>>{};
        final regionalSubnets = <String, Map<String, dynamic>>{};
        for (final selected in compartmentIds) {
          final position = completedScopes + 1;
          final scope = 'region $region, compartment $selected '
              '(scope $position/$scopeCount; $completedScopes completed)';
          for (final kind in ['vcn', 'subnet']) {
            checkCancellation(scopedCancellation);
            final step = kind == 'vcn' ? 'VCN list' : 'subnet list';
            currentOperation = '$step in $scope';
            report('Loading $currentOperation');
            final Object? response;
            try {
              response = await _commands.request(
                  connection,
                  region,
                  [
                    'network',
                    kind,
                    'list',
                    '--compartment-id',
                    selected,
                    '--all'
                  ],
                  cancellation: scopedCancellation,
                  step: currentOperation,
                  listResponse: true);
            } on OciException catch (error) {
              throw OciException('$currentOperation failed: ${error.message}');
            }
            final resources = responseList(response, step: currentOperation);
            _validateResources(resources,
                compartmentId: selected,
                subnets: kind == 'subnet',
                step: currentOperation);
            final target = kind == 'vcn' ? regionalVcns : regionalSubnets;
            for (final resource in resources) {
              final id = resource['id'] as String;
              if (target.containsKey(id)) {
                throw malformedResponse(currentOperation,
                    'field "id" repeated across compartment scopes');
              }
              target[id] = {...resource, 'region': region};
            }
          }
          completedScopes++;
        }
        final missing = regionalSubnets.values
            .map((entry) => entry['vcn-id'] as String)
            .where((id) => !regionalVcns.containsKey(id))
            .toSet();
        var contextNumber = 0;
        for (final id in missing) {
          checkCancellation(scopedCancellation);
          contextNumber++;
          final referringCompartment = regionalSubnets.values
              .firstWhere((entry) => entry['vcn-id'] == id)['compartment-id'];
          currentOperation = 'referenced VCN lookup in region $region, '
              'subnet compartment $referringCompartment '
              '(context $contextNumber/${missing.length}; '
              '$completedScopes/$scopeCount scopes completed)';
          report('Loading $currentOperation');
          try {
            final Object? response;
            try {
              response = await _commands.request(
                  connection, region, ['network', 'vcn', 'get', '--vcn-id', id],
                  cancellation: scopedCancellation, step: currentOperation);
            } on OciCommandFailure catch (error) {
              if (error.unavailableContext) rethrow;
              throw OciException('$currentOperation failed: ${error.message}');
            } on OciException catch (error) {
              throw OciException('$currentOperation failed: ${error.message}');
            }
            final context = responseObject(response, step: currentOperation);
            _validateResources([context], step: currentOperation);
            if (context['id'] != id) {
              throw malformedResponse(currentOperation,
                  'field "id" did not match the requested resource');
            }
            regionalVcns[id] = {...context, 'region': region};
            contextSuccesses.add({'region': region, 'id': id});
            final contextCompartment = context['compartment-id'];
            warnings.add('Referenced VCN $id in region $region was included as '
                'context from compartment $contextCompartment; subnets are '
                'collected only in the requested compartment scopes.');
          } on OciCommandFailure catch (error) {
            if (!error.unavailableContext) rethrow;
            contextFailures.add({'region': region, 'id': id});
            warnings.add('Referenced VCN $id in region $region is unavailable '
                'or access was denied. Its subnet references remain; '
                'this does not prove deletion.');
          }
        }
        vcns.addAll(regionalVcns.values);
        subnets.addAll(regionalSubnets.values);
      }
      checkCancellation(scopedCancellation);
      if (vcns.isEmpty && subnets.isEmpty) {
        warnings.add(allCompartments
            ? 'No VCNs or subnets were returned across the collected regions '
                'and accessible compartments. Check the selected regions, IAM '
                'network permissions and inventory coverage.'
            : 'No VCNs or subnets were returned for the selected compartment '
                'and regions. Discovery includes resources directly in that '
                'compartment; choose a child compartment or all accessible '
                'compartments to discover its resources.');
      }
      final completed = _clock().toUtc();
      final contextIncluded = contextSuccesses
          .map((context) => '${context["id"]} (${context["region"]})')
          .join(', ');
      final contextUnavailable = contextFailures
          .map((context) => '${context["id"]} (${context["region"]})')
          .join(', ');
      final coverage = 'Scoped observation across regions '
          '${selectedRegions.join(", ")}, compartments ${compartmentIds.join(", ")}, '
          'collecting all pages of directly contained VCNs and subnets for '
          '$completedScopes/$scopeCount region/compartment scopes. '
          '${allCompartments ? "Accessible descendants and tenancy root included; IAM-hidden compartments remain outside observed coverage." : "No descendant resource traversal."} '
          'Observation interval ${started.toIso8601String()} to '
          '${completed.toIso8601String()}. '
          'Referenced VCN context included: ${contextIncluded.isEmpty ? "none" : contextIncluded}; '
          'unavailable context: ${contextUnavailable.isEmpty ? "none" : contextUnavailable}. '
          '${warnings.join(" ")} This is not a transactionally consistent '
          'snapshot and not a complete tenancy audit. Omitted resources are '
          'not evidence of deletion or free address space.';
      return OciDiscovery(
          bundleJson: jsonEncode({
            'metadata': {
              'tenancy': connection.tenancyId,
              if (selectedRegions.length == 1) 'region': selectedRegions.single,
              'regions': selectedRegions,
              'compartmentIds': compartmentIds,
              'regionMode': allRegions ? 'allReady' : 'selected',
              'compartmentMode': allCompartments ? 'allAccessible' : 'selected',
              'scopeCount': scopeCount,
              'completedScopeCount': completedScopes,
              'vcnCount': vcns.length,
              'subnetCount': subnets.length,
              'contextIncludedCount': contextSuccesses.length,
              'contextUnavailableCount': contextFailures.length,
              'contextIncluded': contextSuccesses,
              'contextUnavailable': contextFailures,
              'collectionStartedAt': started.toIso8601String(),
              'collectedAt': completed.toIso8601String(),
              'coverage': coverage
            },
            'vcns': vcns,
            'subnets': subnets,
          }),
          warnings: List.unmodifiable(warnings.toSet()));
    } on OciException {
      if (expired) {
        throw OciException('OCI collection timed out during $currentOperation. '
            '$completedScopes/$scopeCount scopes completed; no partial '
            'inventory was returned. Retry a smaller scope or check connectivity.');
      }
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  void _validateResources(List<Map<String, dynamic>> resources,
      {String? compartmentId, bool subnets = false, required String step}) {
    final ids = <String>{};
    for (final resource in resources) {
      if (!ids.add(requiredString(resource, 'id', step: step))) {
        throw malformedResponse(
            step, 'field "id" must be unique within the response');
      }
      final actualCompartment =
          requiredString(resource, 'compartment-id', step: step);
      if (compartmentId != null && actualCompartment != compartmentId) {
        throw malformedResponse(
            step, 'field "compartment-id" did not match the selected scope');
      }
      if (subnets) requiredString(resource, 'vcn-id', step: step);
    }
  }
}
