// CIDR Atlas OCI discovery and import workflow widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

import 'package:cidr_atlas/dialogs.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_oci/cidr_oci.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const bundle =
    '''{"metadata":{"tenancy":"ocid1.tenancy.oc1..fictional","region":"us-phoenix-1","collectedAt":"2026-10-15T20:00:00Z","coverage":"Fictional selected compartment only; omitted resources are retained."},"vcns":[{"id":"ocid1.vcn.oc1..fictional","display-name":"Fictional VCN","compartment-id":"ocid1.compartment.oc1..fictional","cidr-block":"10.64.0.0/16"}],"subnets":[]}''';

class FakeOciInventoryClient implements OciInventoryClient {
  int networkCalls = 0;
  String? requestedConfig;
  String? requestedExecutable;
  OciAuthMode? requestedAuth;
  String? requestedProfile;
  String? requestedRegion;
  String? requestedCompartment;
  OciCancellation? cancellation;
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

  @override
  Future<List<OciCompartment>> compartments(
    OciConnection connection, {
    required String region,
    OciCancellation? cancellation,
  }) async {
    networkCalls++;
    return const [
      OciCompartment(
        id: 'ocid1.compartment.oc1..fictional',
        name: 'Fictional architecture compartment with a deliberately long display name',
      ),
    ];
  }

  @override
  Future<OciDiscovery> discover(
    OciConnection connection, {
    required String region,
    required String compartmentId,
    OciCancellation? cancellation,
    void Function(String)? onProgress,
  }) async {
    networkCalls++;
    this.cancellation = cancellation;
    requestedRegion = region;
    requestedCompartment = compartmentId;
    onProgress?.call('Reading selected VCNs');
    if (pending != null) return pending!.future;
    if (discoveryError != null) throw discoveryError!;
    return OciDiscovery(
      bundleJson: json,
      warnings: const ['Fictional discovery warning'],
    );
  }
}

Future<void> openImport(
  WidgetTester tester,
  FakeOciInventoryClient client, {
  Size size = const Size(1100, 740),
  InventoryStore? store,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final preview = await showDialog<ImportPreview>(
                context: context,
                builder: (_) => ImportDialog(
                  existing: store?.list() ?? [],
                  proposedRecords: store?.mergedImportRecords,
                  ociClient: client,
                ),
              );
              if (preview != null) store?.applyImport(preview);
            },
            child: const Text('Open import'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open import'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Discover from OCI CLI'));
  await tester.pumpAndSettle();
}

Future<void> manualScope(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Enter scope manually'));
  await tester.tap(find.text('Enter scope manually'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('oci-region')),
    'us-phoenix-1',
  );
  await tester.enterText(
    find.byKey(const ValueKey('oci-compartment')),
    'ocid1.compartment.oc1..fictional',
  );
}

Future<void> discover(WidgetTester tester) async {
  await manualScope(tester);
  await tester.enterText(find.byKey(const ValueKey('oci-domain')), 'corporate');
  await tester.tap(find.text('Discover inventory'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('import dialog offers explicit OCI discovery', (tester) async {
    tester.view.physicalSize = const Size(1100, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImportDialog(existing: [])),
      ),
    );
    expect(find.text('Discover from OCI CLI'), findsOneWidget);
  });

  testWidgets(
    'opening discovery reads metadata only and profile selects authentication',
    (tester) async {
      final client = FakeOciInventoryClient();
      await openImport(tester, client);
      expect(find.text('Discover OCI inventory'), findsOneWidget);
      expect(client.networkCalls, 0);
      expect(find.text('ocid1.tenancy.oc1..fictional'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key.toString().contains('oci-profile-'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SESSION').last);
      await tester.pumpAndSettle();
      expect(find.text('Security token'), findsOneWidget);
      await tester.tap(find.text('Load scopes'));
      await tester.pumpAndSettle();
      expect(client.requestedProfile, 'SESSION');
      expect(client.requestedAuth, OciAuthMode.securityToken);
      expect(client.networkCalls, 2);
      expect(find.text('Tenancy root'), findsOneWidget);
      await tester.ensureVisible(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key.toString().contains('oci-region-selector-'),
        ),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.key.toString().contains('oci-region-selector-'),
        ),
      );
      await tester.pumpAndSettle();
      final unready = tester.widget<DropdownMenuItem<String>>(
        find
            .widgetWithText(
              DropdownMenuItem<String>,
              'us-ashburn-1 · IN_PROGRESS',
            )
            .last,
      );
      expect(unready.enabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual scope works after IAM selector failure and requires a routing domain',
    (tester) async {
      final client = FakeOciInventoryClient()
        ..scopeError = const OciException(
          'Access denied. Enter scope manually.',
        );
      await openImport(tester, client);
      await tester.tap(find.text('Load scopes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Access denied'), findsOneWidget);
      await manualScope(tester);
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
      expect(find.text('Routing domain is required'), findsOneWidget);
      expect(client.requestedCompartment, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('oci-domain')),
        'corporate',
      );
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
      expect(find.text('1 prefixes · OCI JSON'), findsOneWidget);
      expect(client.requestedRegion, 'us-phoenix-1');
      expect(client.requestedCompartment, 'ocid1.compartment.oc1..fictional');
    },
  );

  testWidgets(
    'reloading scopes keeps the visible region and discovery region aligned',
    (tester) async {
      final client = FakeOciInventoryClient();
      await openImport(tester, client);
      await tester.tap(find.text('Load scopes'));
      await tester.pumpAndSettle();
      final selector = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.key.toString().contains('oci-region-selector-'),
      );
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('eu-frankfurt-1 · READY').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Load scopes'));
      await tester.tap(find.text('Load scopes'));
      await tester.pumpAndSettle();
      expect(
        tester.state<FormFieldState<String>>(selector).value,
        'us-phoenix-1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('oci-domain')),
        'corporate',
      );
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
      expect(client.requestedRegion, 'us-phoenix-1');
    },
  );

  testWidgets(
    'Cancel terminates discovery and ignores a late successful result',
    (tester) async {
      final client = FakeOciInventoryClient()
        ..pending = Completer<OciDiscovery>();
      await openImport(tester, client);
      await discover(tester);
      expect(find.text('Reading selected VCNs'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      expect(client.cancellation!.isCancelled, isTrue);
      client.pending!.complete(const OciDiscovery(bundleJson: bundle));
      await tester.pumpAndSettle();
      expect(find.text('1 prefixes · OCI JSON'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply import'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('path overrides and explicit authentication reach collection', (
    tester,
  ) async {
    final client = FakeOciInventoryClient();
    await openImport(tester, client);
    await tester.tap(find.text('CLI and configuration paths'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'OCI executable path (optional)'),
      '/fictional/custom-oci',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'OCI configuration path (optional)'),
      '/fictional/alternate-config',
    );
    await tester.ensureVisible(find.text('Reload profiles'));
    await tester.tap(find.text('Reload profiles'));
    await tester.pumpAndSettle();
    expect(client.requestedConfig, '/fictional/alternate-config');
    expect(client.networkCalls, 0);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<OciAuthMode>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<OciAuthMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security token').last);
    await tester.pumpAndSettle();
    await discover(tester);
    await tester.pumpAndSettle();
    expect(client.requestedProfile, 'DEFAULT');
    expect(client.requestedAuth, OciAuthMode.securityToken);
    expect(client.requestedExecutable, '/fictional/custom-oci');
    expect(client.requestedConfig, '/fictional/alternate-config');
  });

  testWidgets(
    'preview and Apply share OCI reconciliation and preserve planning metadata',
    (tester) async {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      store.save(
        const PrefixRecord(
          id: 'planned-vcn',
          cidr: '10.64.0.0/16',
          name: 'Planned VCN',
          routingDomain: 'corporate',
          resourceId: 'ocid1.vcn.oc1..fictional',
          tenancy: 'ocid1.tenancy.oc1..fictional',
          region: 'us-phoenix-1',
          owner: 'Architecture',
          notes: 'Keep planning notes',
          status: PrefixStatus.planned,
        ),
      );
      final client = FakeOciInventoryClient();
      await openImport(tester, client, store: store);
      await discover(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('routing conflict(s)'), findsNothing);
      expect(store.list().single.name, 'Planned VCN');
      await tester.tap(find.text('Apply import'));
      await tester.pumpAndSettle();
      final saved = store.list().single;
      expect(saved.id, 'planned-vcn');
      expect(saved.name, 'Fictional VCN');
      expect(saved.owner, 'Architecture');
      expect(saved.notes, 'Keep planning notes');
      expect(saved.status, PrefixStatus.planned);
      expect(saved.source, 'oci');
    },
  );

  testWidgets(
    'real discovered overlaps stay reviewable and absent prefixes remain after Apply',
    (tester) async {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      store.save(
        const PrefixRecord(
          id: 'other-vcn',
          cidr: '10.64.0.0/24',
          name: 'Existing overlapping VCN',
          routingDomain: 'corporate',
        ),
      );
      final client = FakeOciInventoryClient();
      await openImport(tester, client, store: store);
      await discover(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('1 routing conflict(s)'), findsOneWidget);
      expect(store.list().length, 1);
      await tester.tap(find.text('Apply import'));
      await tester.pumpAndSettle();
      expect(store.list().length, 2);
      expect(store.list().any((record) => record.id == 'other-vcn'), isTrue);
      expect(InventoryRules.conflicts(store.list()).length, 1);
    },
  );

  testWidgets(
    'dismissing during scope loading cancels and ignores late selector results',
    (tester) async {
      final client = FakeOciInventoryClient()
        ..pendingRegions = Completer<List<OciRegion>>();
      await openImport(tester, client);
      await tester.tap(find.text('Load scopes'));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(client.cancellation!.isCancelled, isTrue);
      client.pendingRegions!.complete(const [
        OciRegion(name: 'late-region', status: 'READY'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('late-region'), findsNothing);
      expect(client.networkCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collection errors cannot reach the applicable preview', (
    tester,
  ) async {
    final client = FakeOciInventoryClient()
      ..discoveryError = const OciException(
        'Session expired. Repair the OCI CLI profile.',
      );
    await openImport(tester, client);
    await discover(tester);
    expect(find.textContaining('Session expired'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply import'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply import'),
          )
          .onPressed,
      isNull,
    );
  });

  for (final size in [const Size(1100, 740), const Size(1440, 900)]) {
    testWidgets(
      'preview stays local until explicit Apply at ${size.width.toInt()} width',
      (tester) async {
        final store = InventoryStore.memory();
        addTearDown(store.close);
        final client = FakeOciInventoryClient();
        await openImport(tester, client, size: size, store: store);
        await discover(tester);
        await tester.pumpAndSettle();
        expect(find.text('1 prefixes · OCI JSON'), findsOneWidget);
        expect(store.list(), isEmpty);
        expect(find.text('Fictional discovery warning'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(store.list(), isEmpty);
        await tester.tap(find.text('Open import'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discover from OCI CLI'));
        await tester.pumpAndSettle();
        await discover(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply import'));
        await tester.pumpAndSettle();
        expect(store.list().single.cidr, '10.64.0.0/16');
        expect(store.list().single.routingDomain, 'corporate');
        expect(store.list().single.source, 'oci');
      },
    );
  }

  testWidgets('invalid discovered CIDR stays visible but cannot be applied', (
    tester,
  ) async {
    final client = FakeOciInventoryClient()
      ..json = bundle.replaceFirst('10.64.0.0/16', '10.64.0.1/16');
    await openImport(tester, client);
    await discover(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp('host bits', caseSensitive: false)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply import'),
          )
          .onPressed,
      isNull,
    );
  });
}
