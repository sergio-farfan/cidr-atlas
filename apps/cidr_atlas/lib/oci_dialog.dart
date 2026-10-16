// CIDR Atlas explicit OCI profile, scope, and inventory discovery dialog.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_oci/cidr_oci.dart';
import 'package:flutter/material.dart';

import 'help.dart';

class OciImportSelection {
  const OciImportSelection({
    required this.bundleJson,
    required this.routingDomain,
    this.warnings = const [],
  });
  final String bundleJson;
  final String routingDomain;
  final List<String> warnings;
}

class OciDiscoveryDialog extends StatefulWidget {
  const OciDiscoveryDialog({super.key, this.client, this.domain});
  final OciInventoryClient? client;
  final String? domain;

  @override
  State<OciDiscoveryDialog> createState() => _OciDiscoveryDialogState();
}

class _OciDiscoveryDialogState extends State<OciDiscoveryDialog> {
  final _form = GlobalKey<FormState>();
  final _config = TextEditingController();
  final _executable = TextEditingController();
  final _region = TextEditingController();
  final _compartment = TextEditingController();
  late final TextEditingController _domain;
  late final OciInventoryClient _client;
  List<OciProfile> _profiles = [];
  List<OciRegion> _regions = [];
  List<OciCompartment> _compartments = [];
  OciProfile? _profile;
  OciAuthMode _auth = OciAuthMode.apiKey;
  OciCancellation? _active;
  int _metadataRequest = 0;
  int _scopeRevision = 0;
  bool _loadingProfiles = true;
  bool _manual = false;
  String? _error;
  String? _progress;

  bool get _busy => _active != null || _loadingProfiles;
  String? _optional(TextEditingController field) =>
      field.text.trim().isEmpty ? null : field.text.trim();

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? OciCliClient();
    _domain = TextEditingController(text: widget.domain ?? '');
    _loadProfiles();
  }

  void _cancel() {
    _active?.cancel();
    _active = null;
  }

  @override
  void dispose() {
    _cancel();
    _metadataRequest++;
    for (final field in [
      _config,
      _executable,
      _region,
      _compartment,
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

  void _clearScopes() {
    _scopeRevision++;
    _regions = [];
    _compartments = [];
    _region.text = _profile?.region ?? '';
    _compartment.clear();
    _error = null;
  }

  Future<void> _loadProfiles() async {
    final request = ++_metadataRequest;
    setState(() {
      _loadingProfiles = true;
      _profiles = [];
      _profile = null;
      _clearScopes();
    });
    try {
      final profiles = await _client.profiles(configFile: _optional(_config));
      if (!mounted || request != _metadataRequest) return;
      setState(() {
        _profiles = profiles;
        if (profiles.isEmpty) {
          _error = 'No OCI profiles found. Check the configuration path.';
        } else {
          _selectProfile(profiles.first);
        }
      });
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

  String _message(Object error) => error is OciException
      ? error.message
      : 'Unable to complete OCI discovery. Check the OCI CLI and selected profile.';

  bool _current(OciCancellation cancellation) =>
      mounted && identical(_active, cancellation) && !cancellation.isCancelled;

  OciCancellation _start(String progress) {
    final cancellation = OciCancellation();
    setState(() {
      _active = cancellation;
      _error = null;
      _progress = progress;
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
    final cancellation = _start('Loading subscribed regions and compartments');
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
      setState(() {
        _scopeRevision++;
        _regions = regions;
        _region.text = selected?.name ?? '';
        _compartments = [
          OciCompartment(id: connection.tenancyId, name: 'Tenancy root'),
          ...compartments.where((item) => item.id != connection.tenancyId),
        ];
        _compartment.text = connection.tenancyId;
      });
    } catch (error) {
      if (_current(cancellation)) setState(() => _error = _message(error));
    } finally {
      if (_current(cancellation)) setState(() => _active = null);
    }
  }

  Future<void> _discover() async {
    if (!_form.currentState!.validate()) return;
    final region = _region.text.trim();
    final compartment = _compartment.text.trim();
    final domain = _domain.text.trim();
    final cancellation = _start('Starting OCI inventory discovery');
    try {
      final connection = await _connection();
      if (!_current(cancellation)) return;
      final discovery = await _client.discover(
        connection,
        region: region,
        compartmentId: compartment,
        cancellation: cancellation,
        onProgress: (message) {
          if (_current(cancellation)) setState(() => _progress = message);
        },
      );
      if (!_current(cancellation)) return;
      Navigator.pop(
        context,
        OciImportSelection(
          bundleJson: discovery.bundleJson,
          routingDomain: domain,
          warnings: discovery.warnings,
        ),
      );
    } catch (error) {
      if (_current(cancellation)) setState(() => _error = _message(error));
    } finally {
      if (_current(cancellation)) setState(() => _active = null);
    }
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
      hintText: key == 'oci-domain' ? 'e.g. corporate-connected' : null,
      helperText: key == 'oci-domain'
          ? 'Local overlap-check scope. Use the same name for connected networks.'
          : null,
      helperMaxLines: 3,
    ),
    validator: (value) => _required(value, label),
  );

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
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Read VCNs and subnets in one region and compartment. OCI supplies their network CIDRs; you do not enter a prefix here. Selecting a parent compartment does not include descendants. Review the results before saving locally.',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'oci-profile-${_profiles.map((p) => p.name).join(',')}',
                    ),
                    initialValue: _profile?.name,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'OCI profile'),
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
                    SelectableText(_profile!.tenancyId),
                    Text('Default region: ${_profile!.region}'),
                  ],
                  const SizedBox(height: 18),
                  DropdownButtonFormField<OciAuthMode>(
                    key: ValueKey('oci-auth-${_profile?.name}-${_auth.name}'),
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
                            _clearScopes();
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
                            : () => setState(() => _manual = !_manual),
                        child: Text(
                          _manual
                              ? 'Use scope selectors'
                              : 'Enter scope manually',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_manual) ...[
                    const Text(
                      'Use this when IAM prevents listing scopes. OCI resource access is still checked during discovery.',
                    ),
                    const SizedBox(height: 14),
                    _textField(_region, 'Region', 'oci-region'),
                    const SizedBox(height: 18),
                    _textField(
                      _compartment,
                      'Compartment OCID',
                      'oci-compartment',
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('oci-region-selector-$_scopeRevision'),
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
                          : (value) => _region.text = value ?? '',
                      validator: (value) => _required(value, 'Region'),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      key: ValueKey('oci-compartment-selector-$_scopeRevision'),
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
                      ),
                      items: [
                        for (final compartment in _compartments)
                          DropdownMenuItem(
                            value: compartment.id,
                            child: Text(
                              compartment.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => _compartment.text = value ?? '',
                      validator: (value) => _required(value, 'Compartment'),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _textField(_domain, 'Routing domain', 'oci-domain'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(
                      _loadingProfiles
                          ? 'Reading profile metadata'
                          : _progress ?? 'Working',
                    ),
                  ],
                ],
              ),
            ),
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
