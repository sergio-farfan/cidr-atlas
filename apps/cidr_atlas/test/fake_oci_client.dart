// CIDR Atlas
// Fictional in-memory OCI inventory client shared by the widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

import 'package:cidr_oci/cidr_oci.dart';

const bundle =
    '''{"metadata":{"tenancy":"ocid1.tenancy.oc1..fictional","region":"us-phoenix-1","collectedAt":"2026-10-15T20:00:00Z","coverage":"Fictional selected compartment only; omitted resources are retained."},"vcns":[{"id":"ocid1.vcn.oc1..fictional","display-name":"Fictional VCN","compartment-id":"ocid1.compartment.oc1..fictional","cidr-block":"10.64.0.0/16"}],"subnets":[]}''';

class FakeOciInventoryClient implements OciInventoryClient {
  int networkCalls = 0;
  String? requestedConfig;
  String? requestedExecutable;
  OciAuthMode? requestedAuth;
  String? requestedProfile;
  String? requestedRegion;
  List<String> requestedRegions = [];
  bool requestedAllRegions = false;
  bool requestedAllCompartments = false;
  String? requestedCompartment;
  OciCancellation? cancellation;

  /// The structured progress callback of the latest discovery, so a test can
  /// report scope counts while [pending] is unresolved.
  void Function(OciDiscoveryProgress)? reportProgress;
  Completer<OciDiscovery>? pending;
  Completer<List<OciRegion>>? pendingRegions;
  OciException? scopeError;
  OciException? discoveryError;
  String json = bundle;

  @override
  Future<List<OciProfile>> profiles({String? configFile}) async {
    requestedConfig = configFile;
    return const [
      OciProfile(
        name: 'DEFAULT',
        tenancyId: 'ocid1.tenancy.oc1..fictional',
        region: 'us-phoenix-1',
        authMode: OciAuthMode.apiKey,
      ),
      OciProfile(
        name: 'SESSION',
        tenancyId: 'ocid1.tenancy.oc1..session',
        region: 'us-ashburn-1',
        authMode: OciAuthMode.securityToken,
      ),
    ];
  }

  @override
  Future<OciConnection> connection({
    required String profile,
    String? configFile,
    String? executable,
    OciAuthMode? authMode,
  }) async {
    requestedAuth = authMode;
    requestedProfile = profile;
    requestedConfig = configFile;
    requestedExecutable = executable;
    return OciConnection(
      executable: executable ?? '/fictional/oci',
      configFile: configFile ?? '/fictional/config',
      profile: profile,
      tenancyId: 'ocid1.tenancy.oc1..fictional',
      authMode: authMode ?? OciAuthMode.apiKey,
    );
  }

  @override
  Future<List<OciRegion>> regions(
    OciConnection connection, {
    OciCancellation? cancellation,
  }) async {
    networkCalls++;
    this.cancellation = cancellation;
    if (pendingRegions != null) return pendingRegions!.future;
    if (scopeError != null) throw scopeError!;
    return const [
      OciRegion(name: 'us-phoenix-1', status: 'READY'),
      OciRegion(name: 'us-ashburn-1', status: 'IN_PROGRESS'),
      OciRegion(name: 'eu-frankfurt-1', status: 'READY'),
    ];
  }

  List<OciCompartment> compartmentList = const [
    OciCompartment(
      id: 'ocid1.compartment.oc1..fictional',
      name: 'Fictional architecture compartment with a deliberately long display name',
    ),
  ];

  @override
  Future<List<OciCompartment>> compartments(
    OciConnection connection, {
    required String region,
    OciCancellation? cancellation,
  }) async {
    networkCalls++;
    return compartmentList;
  }

  @override
  Future<OciDiscovery> discover(
    OciConnection connection, {
    List<String> regions = const [],
    bool allRegions = false,
    String? compartmentId,
    bool allCompartments = false,
    OciCancellation? cancellation,
    void Function(String)? onProgress,
    void Function(OciDiscoveryProgress)? onDiscoveryProgress,
  }) async {
    networkCalls++;
    this.cancellation = cancellation;
    requestedRegions = regions;
    requestedRegion = regions.firstOrNull;
    requestedAllRegions = allRegions;
    requestedAllCompartments = allCompartments;
    requestedCompartment = compartmentId;
    reportProgress = onDiscoveryProgress;
    onProgress?.call('Reading selected VCNs');
    onDiscoveryProgress?.call(
      const OciDiscoveryProgress(
        message: 'Reading selected VCNs',
        collectionTimeout: OciCollectionLimits.singleScope,
      ),
    );
    if (pending != null) return pending!.future;
    if (discoveryError != null) throw discoveryError!;
    return OciDiscovery(
      bundleJson: json,
      warnings: const ['Fictional discovery warning'],
    );
  }
}
