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
      {required this.name, required this.status, this.isHome = false});
  final String name, status;
  final bool isHome;
}

class OciCompartment {
  const OciCompartment({required this.id, required this.name});
  final String id, name;
}

class OciDiscovery {
  const OciDiscovery({required this.bundleJson, this.warnings = const []});
  final String bundleJson;
  final List<String> warnings;
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
