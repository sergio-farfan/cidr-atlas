// CIDR Atlas explicit OCI profile, scope, and inventory discovery dialog.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

import 'package:cidr_oci/cidr_oci.dart';
import 'package:flutter/material.dart';

import 'help.dart';

class OciImportSelection {
  const OciImportSelection({
    required this.bundleJson,
    required this.routingDomain,
    this.warnings = const [],
    this.scope,
  });
  final String bundleJson;
  final String routingDomain;
  final List<String> warnings;

  /// The profile and scope this discovery used, so a follow-up discovery can
  /// start from the same choices. Null when the selection was not produced by
  /// [OciDiscoveryDialog].
  final OciDiscoveryScope? scope;
}

/// The profile, connection overrides, and region/compartment scope of one
/// discovery. Used to record what a completed discovery covered and to
/// preset [OciDiscoveryDialog] for a retry.
class OciDiscoveryScope {
  const OciDiscoveryScope({
    required this.profile,
    this.authMode,
    this.configFile,
    this.executable,
    this.regions = const [],
    this.allRegions = false,
    this.compartmentId,
    this.allCompartments = false,
    this.collectionTimeoutMinutes,
  });

  /// OCI CLI profile name.
  final String profile;
  final OciAuthMode? authMode;
  final String? configFile;
  final String? executable;

  /// Selected resource regions; empty when [allRegions] is set.
  final List<String> regions;
  final bool allRegions;

  /// The one compartment read directly; null when [allCompartments] is set.
  final String? compartmentId;
  final bool allCompartments;

  /// The entered collection time limit, or null for the adapter default.
  final int? collectionTimeoutMinutes;

  /// The same profile and regions across all accessible compartments.
  OciDiscoveryScope withAllCompartments() => OciDiscoveryScope(
    profile: profile,
    authMode: authMode,
    configFile: configFile,
    executable: executable,
    regions: regions,
    allRegions: allRegions,
    allCompartments: true,
    collectionTimeoutMinutes: collectionTimeoutMinutes,
  );
}

/// Creates an OCI discovery client bounded by an optional whole-collection
/// time limit; null keeps the adapter default.
typedef OciClientFactory = OciInventoryClient Function({
  Duration? collectionTimeout,
});

class OciDiscoveryDialog extends StatefulWidget {
  const OciDiscoveryDialog({
    super.key,
    this.client,
    this.domain,
    this.clientFactory,
    this.initialScope,
    this.startImmediately = false,
  });
  final OciInventoryClient? client;
  final String? domain;

  /// Presets the profile, connection overrides, and scope, for example to
  /// retry a completed discovery more broadly. Regions are shown as typed
  /// manual scope; a profile that no longer exists is reported, not guessed.
  final OciDiscoveryScope? initialScope;

  /// Starts discovery with [initialScope] as soon as profiles are read, when
  /// the preset profile exists and the form is valid.
  final bool startImmediately;

  /// Creates the discovery client when a collection time limit is entered,
  /// and the metadata client when no [client] is injected. Defaults to
  /// [defaultClientFactory]. An injected [client] without a factory cannot
  /// take the limit itself, so the dialog enforces an entered limit by
  /// cancelling that client's discovery when it expires.
  final OciClientFactory? clientFactory;

  /// The production client: the installed OCI CLI.
  static OciInventoryClient defaultClientFactory({
    Duration? collectionTimeout,
  }) => OciCliClient(collectionTimeout: collectionTimeout);

  /// Upper bound for the optional collection time limit, in minutes.
  static const maxCollectionMinutes = 1440;

  @override
  State<OciDiscoveryDialog> createState() => _OciDiscoveryDialogState();
}

/// The OCI work the progress overlay is reporting.
enum _OciWork { profiles, scopes, discovery }

class _OciDiscoveryDialogState extends State<OciDiscoveryDialog> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _messageKey = GlobalKey();
  final _config = TextEditingController();
  final _executable = TextEditingController();
  final _region = TextEditingController();
  final _compartment = TextEditingController();
  final _timeout = TextEditingController();
  late final TextEditingController _domain;
  late final OciInventoryClient _client;
  List<OciProfile> _profiles = [];
  List<OciRegion> _regions = [];
  List<OciCompartment> _compartments = [];
  OciProfile? _profile;
  OciAuthMode _auth = OciAuthMode.apiKey;
  OciCancellation? _active;
  Timer? _collectionLimit;
  int _metadataRequest = 0;
  int _scopeRevision = 0;
  bool _loadingProfiles = true;
  bool _manual = false;
  bool _allRegions = false;
  bool _allCompartments = false;
  final _additionalRegions = <String>{};
  String? _error;
  String? _notice;
  String? _progress;
  OciDiscoveryProgress? _structured;

  /// The collection time limit in effect for the active discovery.
  Duration? _limit;
  _OciWork _work = _OciWork.profiles;

  /// Identifies one busy period, so the overlay's elapsed time restarts.
  int _operation = 0;
  String? _rootCompartmentId;

  /// [OciDiscoveryDialog.initialScope], applied after the first profile read.
  OciDiscoveryScope? _pendingScope;

  bool get _busy => _active != null || _loadingProfiles;
  String? _optional(TextEditingController field) =>
      field.text.trim().isEmpty ? null : field.text.trim();

  @override
  void initState() {
    super.initState();
    _client =
        widget.client ??
        (widget.clientFactory ?? OciDiscoveryDialog.defaultClientFactory)();
    _domain = TextEditingController(text: widget.domain ?? '');
    final initial = widget.initialScope;
    if (initial != null) {
      _config.text = initial.configFile ?? '';
      _executable.text = initial.executable ?? '';
      _timeout.text = initial.collectionTimeoutMinutes?.toString() ?? '';
      _pendingScope = initial;
    }
    _loadProfiles();
  }

  void _cancel() {
    _collectionLimit?.cancel();
    _collectionLimit = null;
    _active?.cancel();
    _active = null;
  }

  @override
  void dispose() {
    _cancel();
    _metadataRequest++;
    _scroll.dispose();
    for (final field in [
      _config,
      _executable,
      _region,
      _compartment,
      _timeout,
      _domain,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  void _selectProfile(OciProfile profile) {
    _profile = profile;
    _auth = profile.authMode;
    _clearScopes();
  }

  /// Clears loaded selectors. Typed manual scope is kept when
  /// [keepManualScope] is set, such as after an authentication change within
  /// the same profile and tenancy.
  void _clearScopes({bool keepManualScope = false}) {
    _scopeRevision++;
    _regions = [];
    _compartments = [];
    _additionalRegions.clear();
    _rootCompartmentId = null;
    _allRegions = false;
    _allCompartments = false;
    if (!(keepManualScope && _manual)) {
      _region.text = _profile?.region ?? '';
      _compartment.clear();
    }
    _error = null;
  }

  Future<void> _loadProfiles() async {
    final request = ++_metadataRequest;
    setState(() {
      _loadingProfiles = true;
      _work = _OciWork.profiles;
      _operation++;
      _notice = null;
      _profiles = [];
      _profile = null;
      _clearScopes();
    });
    try {
      final profiles = await _client.profiles(configFile: _optional(_config));
      if (!mounted || request != _metadataRequest) return;
      var start = false;
      setState(() {
        _profiles = profiles;
        if (profiles.isEmpty) {
          _pendingScope = null;
          _error = 'No OCI profiles found. Check the configuration path.';
        } else {
          _selectProfile(profiles.first);
          start = _applyInitialScope(profiles);
        }
      });
      if (start && widget.startImmediately) {
        // After the frame that ends profile loading, so the form is built
        // and no longer busy.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_busy) _discover();
        });
      }
    } catch (error) {
      if (mounted && request == _metadataRequest) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && request == _metadataRequest) {
        setState(() => _loadingProfiles = false);
      }
    }
  }

  /// Applies [OciDiscoveryDialog.initialScope] once. Regions are kept as
  /// typed manual scope because selectors are not loaded yet. Returns whether
  /// the preset profile exists, so discovery may start.
  bool _applyInitialScope(List<OciProfile> profiles) {
    final scope = _pendingScope;
    _pendingScope = null;
    if (scope == null) return false;
    final profile = profiles
        .where((profile) => profile.name == scope.profile)
        .firstOrNull;
    if (profile == null) {
      _error =
          'The OCI profile "${scope.profile}" used by the previous discovery '
          'is no longer available. Select a profile and choose the scope '
          'again.';
      return false;
    }
    _selectProfile(profile);
    if (scope.authMode != null) _auth = scope.authMode!;
    _manual = true;
    _scopeRevision++;
    _region.text = scope.regions.isEmpty
        ? profile.region
        : scope.regions.join(', ');
    _allRegions = scope.allRegions;
    _allCompartments = scope.allCompartments;
    _compartment.text = scope.compartmentId ?? '';
    return true;
  }

  /// Scrolls the error or notice into view once it is laid out, so a result
  /// is not hidden below the visible part of the form.
  void _revealMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _messageKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _fail(String message) {
    setState(() => _error = message);
    _revealMessage();
  }

  /// Cancels the work the overlay reports and returns to the form. Discovery
  /// and scope loading use the same cancellation as closing the dialog.
  void _cancelWork() {
    setState(() {
      if (_active != null) {
        final discovery = _work == _OciWork.discovery;
        _cancel();
        _notice = discovery
            ? 'Discovery cancelled. No inventory was returned; adjust the '
                  'scope and discover again.'
            : 'Scope loading cancelled. Load scopes again or enter the scope '
                  'manually.';
      } else if (_loadingProfiles) {
        _metadataRequest++;
        _pendingScope = null;
        _loadingProfiles = false;
        _notice =
            'Profile reading cancelled. Use Reload profiles to try again.';
      }
    });
    _revealMessage();
  }

  String _message(Object error) => error is OciException
      ? error.message
      : 'Unable to complete OCI discovery. Check the OCI CLI and selected profile.';

  bool _current(OciCancellation cancellation) =>
      mounted && identical(_active, cancellation) && !cancellation.isCancelled;

  OciCancellation _start(String progress, _OciWork work, {Duration? limit}) {
    final cancellation = OciCancellation();
    setState(() {
      _active = cancellation;
      _work = work;
      _operation++;
      _error = null;
      _notice = null;
      _progress = progress;
      _structured = null;
      _limit = limit;
    });
    return cancellation;
  }

  Future<OciConnection> _connection() => _client.connection(
    profile: _profile!.name,
    configFile: _optional(_config),
    executable: _optional(_executable),
    authMode: _auth,
  );

  Future<void> _loadScopes() async {
    final cancellation = _start(
      'Loading subscribed regions and compartments',
      _OciWork.scopes,
    );
    try {
      final connection = await _connection();
      if (!_current(cancellation)) return;
      final regions = await _client.regions(
        connection,
        cancellation: cancellation,
      );
      if (!_current(cancellation)) return;
      final ready = regions
          .where((region) => region.status == 'READY')
          .toList();
      final selected =
          ready
              .where((region) => region.name == _profile!.region)
              .firstOrNull ??
          ready.firstOrNull;
      final compartments = await _client.compartments(
        connection,
        region: selected?.name ?? _profile!.region,
        cancellation: cancellation,
      );
      if (!_current(cancellation)) return;
      final children =
          compartments.where((item) => item.id != connection.tenancyId).toList()
            ..sort((a, b) {
              final folded = a.displayPath.toLowerCase().compareTo(
                b.displayPath.toLowerCase(),
              );
              return folded != 0 ? folded : a.id.compareTo(b.id);
            });
      setState(() {
        _scopeRevision++;
        _regions = regions;
        _rootCompartmentId = connection.tenancyId;
        _compartments = [
          OciCompartment(
            id: connection.tenancyId,
            name: 'Tenancy root',
            path: 'Tenancy root',
          ),
          ...children,
        ];
        // Typed manual scope stays exactly as entered; only the selector
        // lists are refreshed.
        if (!_manual) {
          _additionalRegions.clear();
          _region.text = selected?.name ?? '';
          _compartment.text = connection.tenancyId;
        }
      });
    } catch (error) {
      if (_current(cancellation)) _fail(_message(error));
    } finally {
      if (_current(cancellation)) setState(() => _active = null);
    }
  }

  Future<void> _discover() async {
    if (!_form.currentState!.validate()) return;
    // The limit sits in a collapsible section whose field may not be built.
    final timeoutError = _timeoutValidation(_timeout.text);
    if (timeoutError != null) {
      setState(() => _error = timeoutError);
      return;
    }
    final regions = _allRegions ? <String>[] : _selectedRegions;
    final compartment = _compartment.text.trim();
    final domain = _domain.text.trim();
    final timeout = _collectionTimeout;
    final dialogDeadline = timeout != null && _injectedWithoutFactory;
    final scope = OciDiscoveryScope(
      profile: _profile!.name,
      authMode: _auth,
      configFile: _optional(_config),
      executable: _optional(_executable),
      regions: regions,
      allRegions: _allRegions,
      compartmentId: _allCompartments ? null : compartment,
      allCompartments: _allCompartments,
      collectionTimeoutMinutes: timeout?.inMinutes,
    );
    // Provisional until the adapter reports the limit for the resolved scope.
    final defaultLimit = _allRegions || _allCompartments || regions.length > 1
        ? OciCollectionLimits.broadScope
        : OciCollectionLimits.singleScope;
    final cancellation = _start(
      'Starting OCI inventory discovery',
      _OciWork.discovery,
      limit: timeout ?? defaultLimit,
    );
    if (dialogDeadline) {
      _collectionLimit?.cancel();
      _collectionLimit = Timer(timeout, () {
        if (!_current(cancellation)) return;
        cancellation.cancel();
        setState(() => _active = null);
        _fail(
          'OCI discovery did not finish within the '
          '${timeout.inMinutes}-minute collection time limit. No '
          'inventory was returned; retry a smaller scope or raise the '
          'limit.',
        );
      });
    }
    try {
      final connection = await _connection();
      if (!_current(cancellation)) return;
      final discovery = await _discoveryClient(timeout).discover(
        connection,
        regions: regions,
        allRegions: _allRegions,
        compartmentId: _allCompartments ? null : compartment,
        allCompartments: _allCompartments,
        cancellation: cancellation,
        onProgress: (message) {
          if (_current(cancellation)) setState(() => _progress = message);
        },
        onDiscoveryProgress: (progress) {
          if (!_current(cancellation)) return;
          setState(() {
            _structured = progress;
            _progress = progress.message;
            // The dialog's own deadline also bounds an injected client.
            _limit = dialogDeadline && timeout < progress.collectionTimeout
                ? timeout
                : progress.collectionTimeout;
          });
        },
      );
      // `_current` already checks `mounted`; the explicit check lets the
      // analyzer see that `context` is still valid after the await.
      if (!mounted || !_current(cancellation)) return;
      Navigator.pop(
        context,
        OciImportSelection(
          bundleJson: discovery.bundleJson,
          routingDomain: domain,
          warnings: discovery.warnings,
          scope: scope,
        ),
      );
    } catch (error) {
      if (_current(cancellation)) _fail(_message(error));
    } finally {
      if (identical(_active, cancellation)) {
        _collectionLimit?.cancel();
        _collectionLimit = null;
      }
      if (_current(cancellation)) setState(() => _active = null);
    }
  }

  bool get _injectedWithoutFactory =>
      widget.client != null && widget.clientFactory == null;

  /// The optional collection time limit; null keeps the adapter default.
  Duration? get _collectionTimeout {
    final minutes = int.tryParse(_timeout.text.trim());
    return minutes == null ? null : Duration(minutes: minutes);
  }

  /// The client for one discovery. An entered limit goes to the factory;
  /// an injected client without one keeps [_client] under the dialog's own
  /// deadline (see [_discover]).
  OciInventoryClient _discoveryClient(Duration? timeout) {
    if (timeout == null || _injectedWithoutFactory) return _client;
    return (widget.clientFactory ?? OciDiscoveryDialog.defaultClientFactory)(
      collectionTimeout: timeout,
    );
  }

  String? _timeoutValidation(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final minutes = int.tryParse(text);
    if (minutes == null ||
        minutes < 1 ||
        minutes > OciDiscoveryDialog.maxCollectionMinutes) {
      return 'Enter whole minutes from 1 to '
          '${OciDiscoveryDialog.maxCollectionMinutes}, or leave blank.';
    }
    return null;
  }

  List<String> get _selectedRegions => {
    ..._region.text.split(',').map((value) => value.trim()),
    if (!_manual) ..._additionalRegions,
  }.toList();

  String? _regionValidation(String? value) {
    if (_allRegions) return null;
    if (value == null || value.trim().isEmpty) return 'Region is required';
    if (value.split(',').any((region) => region.trim().isEmpty)) {
      return 'Enter region names separated by commas; remove blank entries.';
    }
    return null;
  }

  void _toggleManual() {
    if (!_manual) {
      _region.text = _selectedRegions.join(', ');
    } else {
      final selected = _selectedRegions;
      final ready = _regions
          .where((region) => region.status == 'READY')
          .map((region) => region.name)
          .toSet();
      final available = selected.where(ready.contains).toList();
      _region.text = available.firstOrNull ?? '';
      _additionalRegions
        ..clear()
        ..addAll(available.skip(1));
    }
    _scopeRevision++;
    _manual = !_manual;
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label is required' : null;

  Widget _textField(
    TextEditingController controller,
    String label,
    String key,
  ) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy,
    decoration: InputDecoration(
      labelText: label,
      hintText: key == 'oci-domain'
          ? 'e.g. corporate-connected'
          : key == 'oci-region'
          ? 'us-phoenix-1, eu-frankfurt-1'
          : null,
      helperText: key == 'oci-domain'
          ? 'Local overlap-check scope. Use the same name for connected networks.'
          : key == 'oci-region'
          ? 'Enter one or more resource regions, separated by commas.'
          : null,
      helperMaxLines: 3,
    ),
    validator: (value) => key == 'oci-region'
        ? _regionValidation(value)
        : _required(value, label),
    // The tenancy-root hint follows a typed compartment OCID.
    onChanged: key == 'oci-compartment' ? (_) => setState(() {}) : null,
  );

  /// Whether the one direct compartment selected is the tenancy root.
  bool get _tenancyRootSelected {
    if (_allCompartments) return false;
    final compartment = _compartment.text.trim();
    return compartment.isNotEmpty &&
        (compartment == _rootCompartmentId ||
            compartment == _profile?.tenancyId);
  }

  Widget _progressOverlay() {
    final discovery = _work == _OciWork.discovery;
    return _OciProgressOverlay(
      key: ValueKey('oci-progress-$_operation'),
      title: discovery ? 'Discovering OCI inventory' : 'Loading OCI scopes',
      message: _progress ?? 'Working',
      scopeCount: discovery ? _structured?.scopeCount : null,
      completedScopes: discovery ? _structured?.completedScopes ?? 0 : 0,
      limit: discovery ? _limit : null,
      onCancel: _cancelWork,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<OciImportSelection>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _cancel();
    },
    child: AlertDialog(
      title: const Text('Discover OCI inventory'),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 580),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
                child: Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Read VCNs and subnets across selected regions or all READY regions, in one compartment or all accessible compartments and subcompartments. OCI supplies the network CIDRs; no manual prefix is required. Review one combined preview before saving locally.',
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'oci-profile-${_profiles.map((p) => p.name).join(',')}',
                        ),
                        initialValue: _profile?.name,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'OCI profile',
                        ),
                        items: [
                          for (final profile in _profiles)
                            DropdownMenuItem(
                              value: profile.name,
                              child: Text(
                                profile.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (name) => setState(
                                () => _selectProfile(
                                  _profiles.firstWhere(
                                    (profile) => profile.name == name,
                                  ),
                                ),
                              ),
                      ),
                      if (_profile != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          label: 'Tenancy OCID',
                          child: SelectableText(_profile!.tenancyId),
                        ),
                        Text('Default region: ${_profile!.region}'),
                      ],
                      const SizedBox(height: 18),
                      DropdownButtonFormField<OciAuthMode>(
                        key: ValueKey(
                          'oci-auth-${_profile?.name}-${_auth.name}',
                        ),
                        initialValue: _auth,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Authentication',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: OciAuthMode.apiKey,
                            child: Text('API key'),
                          ),
                          DropdownMenuItem(
                            value: OciAuthMode.securityToken,
                            child: Text('Security token'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                _auth = value!;
                                _clearScopes(keepManualScope: true);
                              }),
                      ),
                      ExpansionTile(
                        title: const Text('CLI and configuration paths'),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          TextField(
                            controller: _executable,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'OCI executable path (optional)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _config,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'OCI configuration path (optional)',
                            ),
                            onChanged: (_) => setState(() {
                              _metadataRequest++;
                              _profiles = [];
                              _profile = null;
                              _clearScopes();
                            }),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _loadProfiles,
                            child: const Text('Reload profiles'),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            key: const ValueKey('oci-collection-timeout'),
                            controller: _timeout,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText:
                                  'Collection time limit, minutes (optional)',
                              helperText:
                                  'Blank keeps the default: 3 minutes for one region '
                                  'and compartment, 30 minutes for broader scopes. '
                                  'A timeout returns no partial inventory.',
                              helperMaxLines: 3,
                            ),
                            validator: _timeoutValidation,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: _busy || _profile == null
                                ? null
                                : _loadScopes,
                            child: const Text('Load scopes'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(_toggleManual),
                            child: Text(
                              _manual
                                  ? 'Use scope selectors'
                                  : 'Enter scope manually',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      CheckboxListTile(
                        key: const ValueKey('oci-all-regions'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('All READY subscribed regions'),
                        subtitle: const Text(
                          'Refresh region subscriptions during discovery.',
                        ),
                        value: _allRegions,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _allRegions = value!),
                      ),
                      if (!_allRegions) ...[
                        if (_manual) ...[
                          const Text(
                            'Enter explicit scopes when IAM prevents listing selectors. Resource IAM permissions still apply.',
                          ),
                          const SizedBox(height: 14),
                          _textField(
                            _region,
                            'Regions (comma-separated)',
                            'oci-region',
                          ),
                        ] else ...[
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'oci-region-selector-$_scopeRevision',
                            ),
                            initialValue:
                                _regions.any(
                                  (region) =>
                                      region.name == _region.text &&
                                      region.status == 'READY',
                                )
                                ? _region.text
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Region (READY only)',
                            ),
                            items: [
                              for (final region in _regions)
                                DropdownMenuItem(
                                  value: region.name,
                                  enabled: region.status == 'READY',
                                  child: Text(
                                    '${region.name} · ${region.status}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                    _region.text = value ?? '';
                                    _additionalRegions.remove(value);
                                  }),
                            validator: _regionValidation,
                          ),
                          if (_regions
                                  .where((region) => region.status == 'READY')
                                  .length >
                              1) ...[
                            const SizedBox(height: 10),
                            const Text('Include additional READY regions'),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final region in _regions.where(
                                  (region) =>
                                      region.status == 'READY' &&
                                      region.name != _region.text,
                                ))
                                  FilterChip(
                                    key: ValueKey(
                                      'oci-extra-region-${region.name}',
                                    ),
                                    label: Text(region.name),
                                    selected: _additionalRegions.contains(
                                      region.name,
                                    ),
                                    onSelected: _busy
                                        ? null
                                        : (selected) => setState(() {
                                            if (selected) {
                                              _additionalRegions.add(
                                                region.name,
                                              );
                                            } else {
                                              _additionalRegions.remove(
                                                region.name,
                                              );
                                            }
                                          }),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ],
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        key: const ValueKey('oci-all-compartments'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'All accessible compartments and subcompartments',
                        ),
                        subtitle: const Text(
                          'Includes tenancy root and accessible active descendants. IAM-hidden compartments may remain unseen.',
                        ),
                        value: _allCompartments,
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _allCompartments = value!),
                      ),
                      if (!_allCompartments) ...[
                        if (_manual)
                          _textField(
                            _compartment,
                            'Compartment OCID',
                            'oci-compartment',
                          )
                        else
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'oci-compartment-selector-$_scopeRevision',
                            ),
                            initialValue:
                                _compartments.any(
                                  (compartment) =>
                                      compartment.id == _compartment.text,
                                )
                                ? _compartment.text
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Compartment',
                              helperText: 'Direct resources only; children require the all-compartments option.',
                              helperMaxLines: 2,
                            ),
                            items: [
                              for (final compartment in _compartments)
                                DropdownMenuItem(
                                  value: compartment.id,
                                  child: Text(
                                    compartment.displayPath,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(
                                    () => _compartment.text = value ?? '',
                                  ),
                            validator: (value) =>
                                _required(value, 'Compartment'),
                          ),
                        if (_tenancyRootSelected)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Tenancy root usually holds no networks; enable all '
                              'accessible compartments to include children.',
                              key: const ValueKey('oci-tenancy-root-hint'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                          ),
                        // Only a compartment the selector actually shows; a typed
                        // OCID that is not in the loaded list leaves it empty.
                        if (!_manual &&
                            _compartments.any(
                              (compartment) =>
                                  compartment.id == _compartment.text,
                            ))
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: SelectableText(
                              'Compartment OCID: ${_compartment.text}',
                              key: const ValueKey('oci-compartment-ocid'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                      const SizedBox(height: 18),
                      _textField(_domain, 'Routing domain', 'oci-domain'),
                      if (_error != null || _notice != null)
                        Padding(
                          key: _messageKey,
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error ?? _notice!,
                              style: _error == null
                                  ? null
                                  : TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Centered over the visible form whatever its scroll position;
              // the barrier blocks the form while OCI work runs. The quick
              // local profile read keeps the form's disabled state instead,
              // so opening the dialog does not flash a modal panel.
              if (_active != null) Positioned.fill(child: _progressOverlay()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('oci-help'),
          onPressed: _busy
              ? null
              : () => showAtlasHelp(context, topic: HelpTopic.ociDiscovery),
          child: const Text('Discovery help'),
        ),
        TextButton(
          onPressed: () {
            _cancel();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _profile == null ? null : _discover,
          child: const Text('Discover inventory'),
        ),
      ],
    ),
  );
}

/// A modal progress panel centered over the discovery form. It reports the
/// current step, region/compartment scope counts when known, elapsed time and
/// the collection limit, and offers Cancel.
class _OciProgressOverlay extends StatefulWidget {
  const _OciProgressOverlay({
    super.key,
    required this.title,
    required this.message,
    required this.onCancel,
    this.scopeCount,
    this.completedScopes = 0,
    this.limit,
  });
  final String title;
  final String message;
  final int? scopeCount;
  final int completedScopes;
  final Duration? limit;
  final VoidCallback onCancel;

  @override
  State<_OciProgressOverlay> createState() => _OciProgressOverlayState();
}

class _OciProgressOverlayState extends State<_OciProgressOverlay> {
  static const _tick = Duration(seconds: 1);
  late final Timer _ticker;
  var _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_tick, (_) => setState(() => _elapsed += _tick));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  static String _clock(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _minutes(Duration value) {
    final seconds = value.inSeconds % 60;
    return seconds == 0
        ? '${value.inMinutes} min'
        : '${value.inMinutes} min $seconds s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.scopeCount;
    final completed = count == null
        ? 0
        : widget.completedScopes.clamp(0, count);
    final limit = widget.limit;
    const detail = TextStyle(fontSize: 12);
    return Stack(
      key: const ValueKey('oci-progress-overlay'),
      children: [
        const ModalBarrier(dismissible: false, color: Color(0x9910151f)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                key: const ValueKey('oci-progress-card'),
                color: scheme.surfaceContainerHighest,
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        key: const ValueKey('oci-progress-bar'),
                        value: count == null || count == 0
                            ? null
                            : completed / count,
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.message,
                          key: const ValueKey('oci-progress-message'),
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '$completed of $count region/compartment scopes',
                          key: const ValueKey('oci-progress-scopes'),
                          style: detail,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Elapsed ${_clock(_elapsed)}',
                        key: const ValueKey('oci-progress-elapsed'),
                        style: detail,
                      ),
                      if (limit != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Collection limit ${_minutes(limit)}; a timeout '
                          'returns no partial inventory.',
                          key: const ValueKey('oci-progress-limit'),
                          style: detail,
                        ),
                      ],
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: const ValueKey('oci-progress-cancel'),
                          onPressed: widget.onCancel,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
