// CIDR Atlas OCI discovery and import workflow widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

import 'package:cidr_atlas/dialogs.dart';
import 'package:cidr_atlas/oci_dialog.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_oci/cidr_oci.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_oci_client.dart';

Future<void> openImport(
  WidgetTester tester,
  FakeOciInventoryClient client, {
  Size size = const Size(1100, 740),
  InventoryStore? store,
  List<PrefixRecord> Function(ImportPreview)? proposedRecords,
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
                  proposedRecords:
                      proposedRecords ?? store?.mergedImportRecords,
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
    'active discovery disables help and completes into import preview',
    (tester) async {
      final client = FakeOciInventoryClient()
        ..pending = Completer<OciDiscovery>();
      await openImport(tester, client);
      await discover(tester);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('oci-help')))
            .onPressed,
        isNull,
      );
      client.pending!.complete(OciDiscovery(bundleJson: bundle));
      await tester.pumpAndSettle();
      expect(find.text('Discover OCI inventory'), findsNothing);
      expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply import'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all scope choices discover without replaced required fields', (
    tester,
  ) async {
    final client = FakeOciInventoryClient()
      ..pending = Completer<OciDiscovery>();
    await openImport(tester, client);
    await tester.ensureVisible(find.byKey(const ValueKey('oci-all-regions')));
    await tester.tap(find.byKey(const ValueKey('oci-all-regions')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('oci-all-compartments')),
    );
    await tester.tap(find.byKey(const ValueKey('oci-all-compartments')));
    await tester.enterText(
      find.byKey(const ValueKey('oci-domain')),
      'corporate',
    );
    await tester.tap(find.text('Discover inventory'));
    await tester.pump();
    expect(client.requestedAllRegions, isTrue);
    expect(client.requestedAllCompartments, isTrue);
    expect(client.requestedRegions, isEmpty);
    expect(client.requestedCompartment, isNull);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('oci-all-regions')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('oci-all-compartments')),
          )
          .onChanged,
      isNull,
    );
    client.pending!.complete(const OciDiscovery(bundleJson: bundle));
    await tester.pumpAndSettle();
    expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('READY regions can be added to one discovery', (tester) async {
    final client = FakeOciInventoryClient();
    await openImport(tester, client);
    await tester.tap(find.text('Load scopes'));
    await tester.pumpAndSettle();
    final additional = find.byKey(
      const ValueKey('oci-extra-region-eu-frankfurt-1'),
    );
    await tester.ensureVisible(additional);
    await tester.tap(additional);
    await tester.enterText(
      find.byKey(const ValueKey('oci-domain')),
      'corporate',
    );
    await tester.tap(find.text('Discover inventory'));
    await tester.pumpAndSettle();
    expect(client.requestedRegions, ['us-phoenix-1', 'eu-frankfurt-1']);
    expect(client.requestedAllRegions, isFalse);
    expect(client.requestedCompartment, 'ocid1.tenancy.oc1..fictional');
    expect(tester.takeException(), isNull);
  });

  for (final allRegions in [true, false]) {
    testWidgets(
      'broad dimensions are independent with all regions $allRegions',
      (tester) async {
        final client = FakeOciInventoryClient();
        await openImport(tester, client);
        await manualScope(tester);
        final option = find.byKey(
          ValueKey(allRegions ? 'oci-all-regions' : 'oci-all-compartments'),
        );
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.enterText(
          find.byKey(const ValueKey('oci-domain')),
          'corporate',
        );
        await tester.tap(find.text('Discover inventory'));
        await tester.pumpAndSettle();
        expect(client.requestedAllRegions, allRegions);
        expect(client.requestedAllCompartments, !allRegions);
        expect(
          client.requestedRegions,
          allRegions ? isEmpty : ['us-phoenix-1'],
        );
        expect(
          client.requestedCompartment,
          allRegions ? 'ocid1.compartment.oc1..fictional' : isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty all-scope result cannot apply and offers scope review', (
    tester,
  ) async {
    final store = InventoryStore.memory();
    addTearDown(store.close);
    final client = FakeOciInventoryClient()..json = '{"vcns":[],"subnets":[]}';
    await openImport(tester, client, store: store);
    for (final key in ['oci-all-regions', 'oci-all-compartments']) {
      final option = find.byKey(ValueKey(key));
      await tester.ensureVisible(option);
      await tester.tap(option);
    }
    await tester.enterText(
      find.byKey(const ValueKey('oci-domain')),
      'corporate',
    );
    await tester.tap(find.text('Discover inventory'));
    await tester.pumpAndSettle();
    expect(
      find.text('Discovery completed — no networks found'),
      findsOneWidget,
    );
    expect(
      find.textContaining('If all compartments are included'),
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
    expect(store.list(), isEmpty);
    expect(store.history(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual selected regions reject blanks and accept comma separated values',
    (tester) async {
      final client = FakeOciInventoryClient();
      await openImport(tester, client);
      await manualScope(tester);
      await tester.enterText(
        find.byKey(const ValueKey('oci-region')),
        'us-phoenix-1, ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('oci-domain')),
        'corporate',
      );
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Enter region names separated by commas; remove blank entries.',
        ),
        findsOneWidget,
      );
      expect(client.networkCalls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('oci-region')),
        'us-phoenix-1, eu-frankfurt-1,us-phoenix-1',
      );
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
      expect(client.requestedRegions, ['us-phoenix-1', 'eu-frankfurt-1']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('discovery help retains scope input without network requests', (
    tester,
  ) async {
    final client = FakeOciInventoryClient();
    await openImport(tester, client);
    await tester.enterText(
      find.byKey(const ValueKey('oci-domain')),
      'fictional-connected',
    );
    await tester.tap(find.byKey(const ValueKey('oci-help')));
    await tester.pumpAndSettle();
    expect(find.text('Discover existing OCI CIDRs'), findsOneWidget);
    expect(client.networkCalls, 0);
    await tester.tap(find.text('Close help'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('oci-domain')))
          .controller!
          .text,
      'fictional-connected',
    );
    expect(find.text('Discover OCI inventory'), findsOneWidget);
    expect(client.networkCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import help retains preview and expandable coverage without writes',
    (tester) async {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      final client = FakeOciInventoryClient();
      await openImport(tester, client, store: store);
      await discover(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-help')));
      await tester.pumpAndSettle();
      expect(find.text('Import files'), findsOneWidget);
      await tester.tap(find.text('Close help'));
      await tester.pumpAndSettle();
      expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
      expect(store.list(), isEmpty);
      expect(store.history(), isEmpty);
      await tester.ensureVisible(find.text('Coverage and observation details'));
      await tester.tap(find.text('Coverage and observation details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reported coverage:'), findsOneWidget);
      expect(
        find.textContaining('Source snapshot observed at'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply import'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening discovery reads metadata only and profile selects authentication',
    (tester) async {
      final client = FakeOciInventoryClient();
      await openImport(tester, client);
      expect(find.text('Discover OCI inventory'), findsOneWidget);
      expect(find.textContaining('Local overlap-check scope'), findsOneWidget);
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
      expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
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
      expect(find.text('1 network CIDR · OCI JSON'), findsNothing);
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
        expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
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

  for (final size in [const Size(1100, 740), const Size(1440, 900)]) {
    testWidgets('empty discovery guides scope selection at $size', (
      tester,
    ) async {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      final client = FakeOciInventoryClient()
        ..json = '{"vcns":[],"subnets":[]}';
      var mergeCalls = 0;
      await openImport(
        tester,
        client,
        size: size,
        store: store,
        proposedRecords: (preview) {
          mergeCalls++;
          return store.mergedImportRecords(preview);
        },
      );
      await discover(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Discovery completed — no networks found'),
        findsOneWidget,
      );
      expect(find.textContaining('No manual CIDR is needed'), findsOneWidget);
      expect(
        find.textContaining('choose the compartment that contains'),
        findsNothing,
      );
      expect(find.textContaining('IAM permissions'), findsOneWidget);
      expect(
        find.textContaining('Import contains no prefix records.'),
        findsNothing,
      );
      expect(mergeCalls, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply import'),
            )
            .onPressed,
        isNull,
      );
      expect(store.list(), isEmpty);
      expect(store.history(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Review discovery scope'));
      await tester.tap(find.text('Review discovery scope'));
      await tester.pumpAndSettle();
      expect(find.text('Discover OCI inventory'), findsOneWidget);
      expect(client.networkCalls, 1);
      client.json = bundle;
      await discover(tester);
      await tester.pumpAndSettle();
      expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
      await tester.tap(find.text('Apply import'));
      await tester.pumpAndSettle();
      expect(store.list().single.cidr, '10.64.0.0/16');
      expect(store.history(), hasLength(1));
    });
  }

  testWidgets('malformed preview is shown once without merged validation', (
    tester,
  ) async {
    final client = FakeOciInventoryClient()..json = '{"vcns":{},"subnets":[]}';
    var mergeCalls = 0;
    await openImport(
      tester,
      client,
      proposedRecords: (_) {
        mergeCalls++;
        throw const FormatException('Unexpected merged validation');
      },
    );
    await discover(tester);
    await tester.pumpAndSettle();
    expect(mergeCalls, 0);
    expect(find.text('Discovery completed — no networks found'), findsNothing);
    final panels = tester
        .widgetList<MessagePanel>(find.byType(MessagePanel))
        .where((panel) => panel.error)
        .toList();
    expect(panels, hasLength(1));
    expect(panels.single.message.split('\n'), hasLength(1));
    expect(panels.single.message, contains('array'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply import'),
          )
          .onPressed,
      isNull,
    );
  });

  Future<void> openDiscovery(
    WidgetTester tester,
    FakeOciInventoryClient client, {
    OciInventoryClient Function({Duration? collectionTimeout})? factory,
  }) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<OciImportSelection>(
                context: context,
                builder: (_) =>
                    OciDiscoveryDialog(client: client, clientFactory: factory),
              ),
              child: const Text('Open discovery'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open discovery'));
    await tester.pumpAndSettle();
  }

  Finder compartmentSelector() => find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.key.toString().contains('oci-compartment-selector-'),
  );

  testWidgets('Load scopes keeps manually typed regions and compartment', (
    tester,
  ) async {
    final client = FakeOciInventoryClient();
    await openImport(tester, client);
    await tester.ensureVisible(find.text('Enter scope manually'));
    await tester.tap(find.text('Enter scope manually'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('oci-region')),
      'eu-frankfurt-1, us-phoenix-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('oci-compartment')),
      'ocid1.compartment.oc1..child',
    );
    await tester.ensureVisible(find.text('Load scopes'));
    await tester.tap(find.text('Load scopes'));
    await tester.pumpAndSettle();
    expect(find.text('eu-frankfurt-1, us-phoenix-1'), findsOneWidget);
    expect(find.text('ocid1.compartment.oc1..child'), findsOneWidget);
    // Switching authentication within the profile keeps typed scope too.
    await tester.ensureVisible(find.text('API key'));
    await tester.tap(find.text('API key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security token').last);
    await tester.pumpAndSettle();
    expect(find.text('ocid1.compartment.oc1..child'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('oci-domain')), 'corp');
    await tester.ensureVisible(find.text('Discover inventory'));
    await tester.tap(find.text('Discover inventory'));
    await tester.pumpAndSettle();
    expect(client.requestedRegions, ['eu-frankfurt-1', 'us-phoenix-1']);
    expect(client.requestedCompartment, 'ocid1.compartment.oc1..child');
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-named compartments show sorted paths and the OCID', (
    tester,
  ) async {
    final client = FakeOciInventoryClient()
      ..compartmentList = const [
        OciCompartment(
          id: 'ocid1.compartment.oc1..prodnet',
          name: 'network',
          parentId: 'ocid1.compartment.oc1..prod',
          path: 'root / prod / network',
        ),
        OciCompartment(
          id: 'ocid1.compartment.oc1..devnet',
          name: 'network',
          parentId: 'ocid1.compartment.oc1..dev',
          path: 'root / dev / network',
        ),
      ];
    await openDiscovery(tester, client);
    await tester.tap(find.text('Load scopes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Compartment OCID: ocid1.tenancy.oc1..fictional'),
      findsOneWidget,
    );
    await tester.ensureVisible(compartmentSelector());
    await tester.tap(compartmentSelector());
    await tester.pumpAndSettle();
    final dev = tester.getTopLeft(find.text('root / dev / network').last);
    final prod = tester.getTopLeft(find.text('root / prod / network').last);
    expect(dev.dy, lessThan(prod.dy));
    expect(find.text('network'), findsNothing);
    await tester.tap(find.text('root / prod / network').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Compartment OCID: ocid1.compartment.oc1..prodnet'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('oci-domain')), 'corp');
    await tester.tap(find.text('Discover inventory'));
    await tester.pumpAndSettle();
    expect(client.requestedCompartment, 'ocid1.compartment.oc1..prodnet');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the compartment OCID line follows the selector, not typed text',
    (tester) async {
      final client = FakeOciInventoryClient();
      await openDiscovery(tester, client);
      await tester.tap(find.text('Load scopes'));
      await tester.pumpAndSettle();
      expect(
        find.text('Compartment OCID: ocid1.tenancy.oc1..fictional'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Enter scope manually'));
      await tester.tap(find.text('Enter scope manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('oci-compartment')),
        'ocid1.compartment.oc1..typedbutunlisted',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use scope selectors'));
      await tester.tap(find.text('Use scope selectors'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('oci-compartment-ocid')), findsNothing);
      expect(
        find.textContaining('ocid1.compartment.oc1..typedbutunlisted'),
        findsNothing,
      );
      // Choosing a listed compartment shows its OCID again.
      await tester.ensureVisible(compartmentSelector());
      await tester.tap(compartmentSelector());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tenancy root').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Compartment OCID: ocid1.tenancy.oc1..fictional'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  group('collection time limit', () {
    Future<void> discoverWithLimit(WidgetTester tester, String limit) async {
      await tester.tap(find.text('CLI and configuration paths'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('oci-collection-timeout')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('oci-collection-timeout')),
        limit,
      );
      await manualScope(tester);
      await tester.enterText(find.byKey(const ValueKey('oci-domain')), 'corp');
      await tester.ensureVisible(find.text('Discover inventory'));
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
    }

    testWidgets('an entered limit creates the collection client with it', (
      tester,
    ) async {
      final client = FakeOciInventoryClient();
      final collector = FakeOciInventoryClient();
      Duration? requested;
      await openDiscovery(
        tester,
        client,
        factory: ({Duration? collectionTimeout}) {
          requested = collectionTimeout;
          return collector;
        },
      );
      await discoverWithLimit(tester, '45');
      expect(requested, const Duration(minutes: 45));
      expect(
        collector.requestedCompartment,
        'ocid1.compartment.oc1..fictional',
      );
      expect(client.requestedCompartment, isNull);
      expect(find.text('Discover OCI inventory'), findsNothing);
    });

    testWidgets('a blank limit keeps the default client', (tester) async {
      final client = FakeOciInventoryClient();
      var created = false;
      await openDiscovery(
        tester,
        client,
        factory: ({Duration? collectionTimeout}) {
          created = true;
          return client;
        },
      );
      await discoverWithLimit(tester, '');
      expect(created, isFalse);
      expect(client.requestedCompartment, 'ocid1.compartment.oc1..fictional');
    });

    testWidgets('an injected client without a factory is still bounded', (
      tester,
    ) async {
      final client = FakeOciInventoryClient()
        ..pending = Completer<OciDiscovery>();
      await openDiscovery(tester, client);
      await tester.tap(find.text('CLI and configuration paths'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('oci-collection-timeout')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('oci-collection-timeout')),
        '2',
      );
      await manualScope(tester);
      await tester.enterText(find.byKey(const ValueKey('oci-domain')), 'corp');
      await tester.ensureVisible(find.text('Discover inventory'));
      await tester.tap(find.text('Discover inventory'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(client.requestedCompartment, 'ocid1.compartment.oc1..fictional');
      expect(client.cancellation?.isCancelled, isFalse);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(client.cancellation?.isCancelled, isTrue);
      expect(
        find.textContaining('did not finish within the 2-minute collection'),
        findsOneWidget,
      );
      // The dialog stays open for a retry with nothing returned.
      expect(find.text('Discover OCI inventory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a discovery that finishes in time leaves no limit pending', (
      tester,
    ) async {
      final client = FakeOciInventoryClient();
      await openDiscovery(tester, client);
      await discoverWithLimit(tester, '5');
      expect(client.requestedCompartment, 'ocid1.compartment.oc1..fictional');
      expect(find.text('Discover OCI inventory'), findsNothing);
      // No limit timer survives the closed dialog to report a late error;
      // the test binding also fails on a timer left pending.
      await tester.pump(const Duration(minutes: 6));
      expect(find.textContaining('did not finish within'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final invalid in ['0', '1441', 'soon']) {
      testWidgets('limit "$invalid" is rejected before collection', (
        tester,
      ) async {
        final client = FakeOciInventoryClient();
        var created = false;
        await openDiscovery(
          tester,
          client,
          factory: ({Duration? collectionTimeout}) {
            created = true;
            return client;
          },
        );
        await discoverWithLimit(tester, invalid);
        expect(created, isFalse);
        expect(client.networkCalls, 0);
        expect(
          find.textContaining('Enter whole minutes from 1 to 1440'),
          findsWidgets,
        );
        expect(find.text('Discover OCI inventory'), findsOneWidget);
      });
    }
  });

  testWidgets('OCI errors are announced and the tenancy OCID is labeled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final client = FakeOciInventoryClient()
      ..scopeError = const OciException('Access denied. Enter scope manually.');
    await openDiscovery(tester, client);
    expect(
      tester.getSemantics(find.text('ocid1.tenancy.oc1..fictional')).label,
      contains('Tenancy OCID'),
    );
    await tester.tap(find.text('Load scopes'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Access denied. Enter scope manually.')),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  group('progress overlay', () {
    Finder formScrollable() => find
        .descendant(
          of: find.ancestor(
            of: find.byType(Form),
            matching: find.byType(SingleChildScrollView),
          ),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> startPendingDiscovery(
      WidgetTester tester,
      FakeOciInventoryClient client,
    ) async {
      await openDiscovery(tester, client);
      await manualScope(tester);
      await tester.enterText(find.byKey(const ValueKey('oci-domain')), 'corp');
      await tester.ensureVisible(find.text('Discover inventory'));
      await tester.tap(find.text('Discover inventory'));
      await tester.pump();
    }

    testWidgets(
      'stays centered in view while the form is scrolled to the top',
      (tester) async {
        final client = FakeOciInventoryClient()
          ..pending = Completer<OciDiscovery>();
        await startPendingDiscovery(tester, client);
        final position = tester
            .state<ScrollableState>(formScrollable())
            .position;
        expect(position.maxScrollExtent, greaterThan(0));
        position.jumpTo(0);
        await tester.pump();
        expect(position.pixels, 0);
        final viewport = tester.getRect(formScrollable());
        final card = tester.getRect(
          find.byKey(const ValueKey('oci-progress-card')),
        );
        expect(viewport.contains(card.topLeft), isTrue);
        expect(viewport.contains(card.bottomRight), isTrue);
        expect((card.center.dy - viewport.center.dy).abs(), lessThan(2));
        expect(
          find.byKey(const ValueKey('oci-progress-cancel')).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Discovering OCI inventory'), findsOneWidget);
        expect(
          find.text('Reading selected VCNs').hitTestable(),
          findsOneWidget,
        );
        // The barrier blocks the form underneath.
        expect(find.text('OCI profile').hitTestable(), findsNothing);
        expect(find.text('Elapsed 00:00'), findsOneWidget);
        await tester.pump(const Duration(seconds: 65));
        expect(find.text('Elapsed 01:05'), findsOneWidget);
        client.pending!.complete(const OciDiscovery(bundleJson: bundle));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('oci-progress-overlay')),
          findsNothing,
        );
        expect(find.text('Discover OCI inventory'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('shows structured scope counts and the collection limit', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final client = FakeOciInventoryClient()
        ..pending = Completer<OciDiscovery>();
      await startPendingDiscovery(tester, client);
      expect(
        find.text(
          'Collection limit 3 min; a timeout returns no partial inventory.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('oci-progress-scopes')), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('oci-progress-bar')),
            )
            .value,
        isNull,
      );
      client.reportProgress!(
        const OciDiscoveryProgress(
          message: 'Reading VCNs in us-phoenix-1 / fictional-network',
          collectionTimeout: OciCollectionLimits.broadScope,
          scopeCount: 4,
          completedScopes: 1,
        ),
      );
      await tester.pump();
      expect(find.text('1 of 4 region/compartment scopes'), findsOneWidget);
      expect(
        find.text(
          'Collection limit 30 min; a timeout returns no partial inventory.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('oci-progress-bar')),
            )
            .value,
        .25,
      );
      expect(
        tester.getSemantics(
          find.text('Reading VCNs in us-phoenix-1 / fictional-network'),
        ),
        isSemantics(isLiveRegion: true),
      );
      client.pending!.complete(const OciDiscovery(bundleJson: bundle));
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('Cancel stops discovery and returns to the form', (
      tester,
    ) async {
      final client = FakeOciInventoryClient()
        ..pending = Completer<OciDiscovery>();
      await startPendingDiscovery(tester, client);
      await tester.tap(find.byKey(const ValueKey('oci-progress-cancel')));
      await tester.pump();
      expect(client.cancellation!.isCancelled, isTrue);
      expect(find.byKey(const ValueKey('oci-progress-overlay')), findsNothing);
      client.pending!.complete(const OciDiscovery(bundleJson: bundle));
      await tester.pumpAndSettle();
      // The late result is ignored; the dialog stays for another attempt.
      expect(find.text('Discover OCI inventory'), findsOneWidget);
      expect(
        find.textContaining('Discovery cancelled. No inventory was returned'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Discover inventory'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cancel stops scope loading', (tester) async {
      final client = FakeOciInventoryClient()
        ..pendingRegions = Completer<List<OciRegion>>();
      await openDiscovery(tester, client);
      await tester.tap(find.text('Load scopes'));
      await tester.pump();
      expect(find.text('Loading OCI scopes'), findsOneWidget);
      expect(find.byKey(const ValueKey('oci-progress-limit')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('oci-progress-cancel')));
      await tester.pump();
      expect(client.cancellation!.isCancelled, isTrue);
      client.pendingRegions!.complete(const [
        OciRegion(name: 'late-region', status: 'READY'),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Scope loading cancelled'), findsOneWidget);
      expect(find.text('late-region'), findsNothing);
      expect(find.text('Discover OCI inventory'), findsOneWidget);
    });

    testWidgets('closes on error and the error is scrolled into view', (
      tester,
    ) async {
      final client = FakeOciInventoryClient()
        ..pending = Completer<OciDiscovery>();
      await startPendingDiscovery(tester, client);
      tester.state<ScrollableState>(formScrollable()).position.jumpTo(0);
      await tester.pump();
      client.pending!.completeError(
        const OciException('Session expired. Repair the OCI CLI profile.'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('oci-progress-overlay')), findsNothing);
      expect(
        find.text('Session expired. Repair the OCI CLI profile.').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Discover OCI inventory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a direct tenancy root compartment explains child coverage', (
    tester,
  ) async {
    const hint =
        'Tenancy root usually holds no networks; enable all accessible '
        'compartments to include children.';
    final client = FakeOciInventoryClient();
    await openDiscovery(tester, client);
    expect(find.text(hint), findsNothing);
    await tester.tap(find.text('Load scopes'));
    await tester.pumpAndSettle();
    // Load scopes selects the tenancy root.
    expect(find.text(hint), findsOneWidget);
    await tester.ensureVisible(compartmentSelector());
    await tester.tap(compartmentSelector());
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining('Fictional architecture compartment').last,
    );
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    await tester.ensureVisible(find.text('Enter scope manually'));
    await tester.tap(find.text('Enter scope manually'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('oci-compartment')),
      'ocid1.tenancy.oc1..fictional',
    );
    await tester.pump();
    expect(find.text(hint), findsOneWidget);
    final all = find.byKey(const ValueKey('oci-all-compartments'));
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('retry with all accessible compartments', () {
    testWidgets('an empty direct-compartment result retries more broadly', (
      tester,
    ) async {
      final client = FakeOciInventoryClient()
        ..json = '{"vcns":[],"subnets":[]}';
      await openImport(tester, client);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<OciAuthMode>),
      );
      await tester.tap(find.byType(DropdownButtonFormField<OciAuthMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Security token').last);
      await tester.pumpAndSettle();
      await discover(tester);
      await tester.pumpAndSettle();
      expect(client.requestedAllCompartments, isFalse);
      expect(
        find.text('Discovery completed — no networks found'),
        findsOneWidget,
      );
      final retry = find.byKey(const ValueKey('oci-retry-all-compartments'));
      expect(
        find.text('Retry with all accessible compartments'),
        findsOneWidget,
      );
      client.json = bundle;
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      // Discovery started without another click, with the same choices.
      expect(client.networkCalls, 2);
      expect(client.requestedAllCompartments, isTrue);
      expect(client.requestedCompartment, isNull);
      expect(client.requestedRegions, ['us-phoenix-1']);
      expect(client.requestedAllRegions, isFalse);
      expect(client.requestedProfile, 'DEFAULT');
      expect(client.requestedAuth, OciAuthMode.securityToken);
      expect(find.text('Discover OCI inventory'), findsNothing);
      expect(find.text('1 network CIDR · OCI JSON'), findsOneWidget);
      expect(find.text('Fictional VCN'), findsOneWidget);
      expect(find.text('corporate'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty all-compartments result offers no retry', (
      tester,
    ) async {
      final client = FakeOciInventoryClient()
        ..json = '{"vcns":[],"subnets":[]}';
      await openImport(tester, client);
      await manualScope(tester);
      final all = find.byKey(const ValueKey('oci-all-compartments'));
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.enterText(
        find.byKey(const ValueKey('oci-domain')),
        'corporate',
      );
      await tester.tap(find.text('Discover inventory'));
      await tester.pumpAndSettle();
      expect(
        find.text('Discovery completed — no networks found'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('oci-retry-all-compartments')),
        findsNothing,
      );
      expect(find.text('Review discovery scope'), findsOneWidget);
    });

    testWidgets('a preset profile that no longer exists does not start', (
      tester,
    ) async {
      final client = FakeOciInventoryClient();
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OciDiscoveryDialog(
              client: client,
              domain: 'corp',
              initialScope: const OciDiscoveryScope(
                profile: 'RETIRED',
                regions: ['us-phoenix-1'],
                allCompartments: true,
              ),
              startImmediately: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(client.networkCalls, 0);
      expect(
        find.textContaining('The OCI profile "RETIRED" used by the previous'),
        findsOneWidget,
      );
    });
  });
}
