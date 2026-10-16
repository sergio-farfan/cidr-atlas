// CIDR Atlas — Immutable OCI selection metadata and cancellation lifecycle.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

enum OciAuthMode { apiKey, securityToken }

class OciProfile {
  const OciProfile(
      {required this.name,
      required this.tenancyId,
      required this.region,
      required this.authMode});
  final String name, tenancyId, region;
  final OciAuthMode authMode;
}

class OciConnection {
  const OciConnection(
      {required this.executable,
      required this.configFile,
      required this.profile,
      required this.tenancyId,
      required this.authMode});
  final String executable, configFile, profile, tenancyId;
  final OciAuthMode authMode;
}

class OciRegion {
  const OciRegion(
      {required this.name,
      required this.status,
      this.isHome = false,
      this.key});
  final String name, status;
  final bool isHome;

  /// Short region key reported by the subscription list, such as `IAD`.
  final String? key;
}

class OciCompartment {
  const OciCompartment(
      {required this.id, required this.name, this.parentId, this.path});
  final String id, name;

  /// Parent compartment OCID, when the listing reported one.
  final String? parentId;

  /// Display path from the tenancy root, such as `root / prod / network`.
  /// A leading `…` segment marks an ancestor that was not listed.
  final String? path;

  /// The path when known, otherwise the compartment name.
  String get displayPath => path ?? name;
}

class OciDiscovery {
  const OciDiscovery({required this.bundleJson, this.warnings = const []});
  final String bundleJson;
  final List<String> warnings;
}

/// One structured discovery progress event, delivered with the same [message]
/// text that the plain `onProgress` callback receives.
class OciDiscoveryProgress {
  const OciDiscoveryProgress(
      {required this.message,
      required this.collectionTimeout,
      this.scopeCount,
      this.completedScopes = 0});

  /// The human-readable progress line.
  final String message;

  /// The whole-collection time limit in effect: the explicit collection
  /// timeout, or the default for the resolved scope
  /// ([OciCollectionLimits.singleScope] or [OciCollectionLimits.broadScope]).
  final Duration collectionTimeout;

  /// The number of region/compartment scopes, or null until region and
  /// compartment enumeration has finished.
  final int? scopeCount;

  /// The number of region/compartment scopes collected so far.
  final int completedScopes;
}

/// Default whole-collection time limits used when no explicit collection
/// timeout is set.
abstract final class OciCollectionLimits {
  /// One region and one compartment.
  static const singleScope = Duration(seconds: 180);

  /// All READY regions, all accessible compartments, or more than one
  /// distinct region after region keys are resolved.
  static const broadScope = Duration(seconds: 1800);
}

class OciCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class OciException implements Exception {
  const OciException(this.message);
  final String message;
  @override
  String toString() => message;
}
