// CIDR Atlas
// Desktop workspace and dialog widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/app.dart';
import 'package:cidr_atlas/controller.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_atlas/dialogs.dart';
import 'package:cidr_atlas/oci_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_oci_client.dart';

void main() {
  late InventoryStore store;
  late AtlasController controller;

  setUp(() {
    store = InventoryStore.memory();
    controller = AtlasController(store, databasePath: ':memory:');
  });
  tearDown(() {
    controller.dispose();
    store.close();
  });

  Future<void> workspace(
    WidgetTester tester, {
    double width = 1440,
    double height = 900,
    FakeOciInventoryClient? ociClient,
    OciClientFactory? ociClientFactory,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AtlasApp(
        controller: controller,
        ociClient: ociClient,
        ociClientFactory: ociClientFactory,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('new inventory starts empty and sample data requires a click', (
    tester,
  ) async {
    await workspace(tester, width: 1100, height: 740);
    expect(find.text('Build your address map'), findsOneWidget);
    expect(find.text('Production VCN'), findsNothing);
    expect(controller.records, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Explore with fictional sample data'));
    await tester.tap(find.text('Explore with fictional sample data'));
    await tester.pumpAndSettle();
    expect(controller.records.length, 6);
    expect(find.text('Build your address map'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Production VCN'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Production VCN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace help explains discovery and manual prefix entry', (
    tester,
  ) async {
    await workspace(tester, width: 1100, height: 740);
    await tester.tap(find.byTooltip('Help and examples'));
    await tester.pumpAndSettle();
    expect(find.text('Help and examples'), findsWidgets);
    expect(find.textContaining('OCI discovery'), findsWidgets);
    expect(controller.records, isEmpty);
    await tester.tap(find.text('Close help'));
    await tester.pumpAndSettle();
    expect(find.text('Build your address map'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1100, 740), const Size(1440, 900)]) {
    testWidgets(
      'inventory selection and filters remain usable at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        controller.loadDemo();
        await workspace(tester, width: size.width, height: size.height);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text('Production VCN'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.ensureVisible(find.text('Production VCN'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Production VCN'));
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        expect(controller.selected?.id, 'demo-vcn');
        expect(find.text('PREFIX DETAILS'), findsOneWidget);
        expect(find.text('Total addresses'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (size.width == 1100) {
          expect(find.byType(Dialog), findsOneWidget);
          await tester.tapAt(const Offset(1090, 730));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        } else {
          expect(find.byType(Dialog), findsNothing);
        }

        await tester.tap(find.byType(DropdownButtonFormField<PrefixStatus?>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reserved').last);
        await tester.pumpAndSettle();
        expect(controller.status, PrefixStatus.reserved);
        expect(find.text('AI platform reservation'), findsOneWidget);
        expect(
          find.text('Production VCN'),
          size.width == 1100 ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editor rejects a CIDR with host bits and keeps inventory empty',
    (tester) async {
      await workspace(tester);
      await tester.tap(find.text('New prefix'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('editor-name')),
        'Invalid network',
      );
      await tester.enterText(
        find.byKey(const ValueKey('editor-cidr')),
        '10.64.0.1/24',
      );
      await tester.enterText(
        find.byKey(const ValueKey('editor-routingDomain')),
        'corporate',
      );
      await tester.tap(find.text('Save prefix'));
      await tester.pumpAndSettle();
      expect(controller.records, isEmpty);
      expect(
        find.textContaining(RegExp('host bits', caseSensitive: false)),
        findsOneWidget,
      );
      expect(find.text('Save prefix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving a valid prefix updates inventory and selection', (
    tester,
  ) async {
    await workspace(tester);
    await tester.tap(find.text('New prefix'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-name')),
      'Architecture VCN',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-cidr')),
      '10.64.0.0/20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-routingDomain')),
      'corporate',
    );
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(controller.records.single.cidr, '10.64.0.0/20');
    expect(controller.selected?.name, 'Architecture VCN');
    expect(find.text('Build your address map'), findsNothing);
    expect(find.text('PREFIX DETAILS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner finds ranges within an explicitly selected pool', (
    tester,
  ) async {
    controller.loadDemo();
    await workspace(tester);
    await tester.tap(find.text('Planner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-domain')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('demo-corporate').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-pool')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Western region allocation').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('planner-calculate')));
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
    expect(find.text('10.64.32.0/24'), findsWidgets);
    expect(find.text('10.64.0.0/24'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overlapping new record needs an explicit conflict override', (
    tester,
  ) async {
    controller.save(
      const PrefixRecord(
        id: 'existing',
        cidr: '10.64.0.0/20',
        name: 'Existing VCN',
        routingDomain: 'corporate',
      ),
    );
    await workspace(tester);
    await tester.tap(find.text('New prefix'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-name')),
      'Overlapping VCN',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-cidr')),
      '10.64.0.0/21',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-routingDomain')),
      'corporate',
    );
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(controller.records.length, 1);
    expect(find.text('Save with conflicts'), findsOneWidget);
    await tester.tap(find.text('Save with conflicts'));
    await tester.pumpAndSettle();
    expect(controller.records.length, 2);
    expect(controller.conflicts.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CIDR checker clears its result after the candidate changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CheckerDialog(records: [], domain: 'corporate'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '10.64.0.0/20');
    await tester.tap(find.text('Check CIDR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('has no conflicts'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '10.64.0.1/20');
    await tester.pumpAndSettle();
    expect(find.textContaining('has no conflicts'), findsNothing);
  });

  testWidgets('retiring a selected planner pool clears the dropdown safely', (
    tester,
  ) async {
    controller.loadDemo();
    await workspace(tester);
    await tester.tap(find.text('Planner'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-domain')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('demo-corporate').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('planner-pool')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Western region allocation').last);
    await tester.pumpAndSettle();
    final pool = controller.records.firstWhere((r) => r.id == 'demo-pool');
    controller.save(pool.copyWith(status: PrefixStatus.retired));
    await tester.pumpAndSettle();
    expect(find.text('Enter a range manually'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> openDetailsEditor(WidgetTester tester, String name) async {
    controller.select(
      controller.records.firstWhere((record) => record.name == name).id,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit prefix'));
    await tester.pumpAndSettle();
  }

  testWidgets('sample records are labeled demo and removed in one change', (
    tester,
  ) async {
    controller.loadDemo();
    expect(controller.records.map((r) => r.source).toSet(), {'demo'});
    store.save(
      const PrefixRecord(
        id: 'real',
        cidr: '172.16.0.0/16',
        name: 'Fictional real allocation',
        routingDomain: 'corporate',
        kind: PrefixKind.allocation,
      ),
    );
    controller.refresh();
    await workspace(tester);
    final history = store.history().length;
    await tester.tap(find.byKey(const ValueKey('remove-sample-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove sample data'));
    await tester.pumpAndSettle();
    expect(controller.records.map((r) => r.id), ['real']);
    expect(store.history().length, history + 1);
    expect(find.byKey(const ValueKey('remove-sample-data')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('version 0.3.0 unlabeled sample records are also removable', (
    tester,
  ) async {
    controller.loadDemo();
    store.saveAll([
      for (final record in store.list()) record.copyWith(source: ''),
    ]);
    controller.refresh();
    expect(controller.hasDemoRecords, isTrue);
    controller.removeDemo();
    expect(controller.records, isEmpty);
  });

  testWidgets('sample removal is refused while a user record depends on it', (
    tester,
  ) async {
    controller.loadDemo();
    controller.reserve(
      const PrefixRecord(
        id: 'user-subnet',
        cidr: '10.64.8.0/24',
        name: 'Fictional user subnet',
        routingDomain: 'demo-corporate',
        kind: PrefixKind.subnet,
        parentId: 'demo-vcn',
        tenancy: 'demo-tenancy',
        region: 'us-phoenix-1',
        vcnId: 'demo-vcn-resource',
        source: 'planner',
      ),
    );
    await workspace(tester);
    await tester.tap(find.byKey(const ValueKey('remove-sample-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove sample data'));
    await tester.pumpAndSettle();
    expect(find.text('Could not complete the change'), findsOneWidget);
    expect(find.textContaining('Cannot delete Production VCN'), findsOneWidget);
    expect(controller.records.length, 7);
  });

  testWidgets('sample data is refused once another process wrote records', (
    tester,
  ) async {
    await workspace(tester, width: 1100, height: 740);
    // cidrctl writes to the shared database; this window has not refreshed.
    store.save(
      const PrefixRecord(
        id: 'cli-record',
        cidr: '10.80.0.0/16',
        name: 'Fictional CLI record',
        routingDomain: 'corporate',
      ),
    );
    await tester.ensureVisible(find.text('Explore with fictional sample data'));
    await tester.tap(find.text('Explore with fictional sample data'));
    await tester.pumpAndSettle();
    expect(find.text('Could not complete the change'), findsOneWidget);
    expect(find.textContaining('no longer empty'), findsOneWidget);
    expect(store.list().map((r) => r.id), ['cli-record']);
    expect(controller.records.map((r) => r.id), ['cli-record']);
  });

  testWidgets('deleting a parent explains which children block it', (
    tester,
  ) async {
    controller.loadDemo();
    await workspace(tester);
    controller.select('demo-pool');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete prefix'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete prefix'));
    await tester.pumpAndSettle();
    expect(find.text('Could not complete the change'), findsOneWidget);
    expect(
      find.textContaining(
        'Cannot delete Western region allocation (10.64.0.0/16): '
        '2 child prefixes reference it',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('does not exist'), findsNothing);
    expect(store.list().length, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a leaf removes it and clears the selection', (
    tester,
  ) async {
    controller.loadDemo();
    await workspace(tester);
    controller.select('demo-db');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete prefix'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete prefix'));
    await tester.pumpAndSettle();
    expect(store.list().any((r) => r.id == 'demo-db'), isFalse);
    expect(controller.selectedId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('observed OCI identity is read-only while planning fields save', (
    tester,
  ) async {
    store.applyImport(InventoryImport.json(bundle, routingDomain: 'corporate'));
    controller.refresh();
    final imported = controller.records.single;
    expect(imported.source, 'oci');
    await workspace(tester);
    await openDetailsEditor(tester, imported.name);
    expect(find.text('Edit prefix'), findsWidgets);
    TextField field(String key) => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(ValueKey('editor-$key')),
        matching: find.byType(TextField),
      ),
    );
    for (final key in ['name', 'cidr', 'routingDomain']) {
      expect(field(key).readOnly, isTrue, reason: key);
    }
    expect(field('notes').readOnly, isFalse);
    expect(
      find.textContaining('Observed by OCI discovery; refresh from OCI'),
      findsWidgets,
    );
    await tester.ensureVisible(find.text('Ownership & OCI metadata'));
    await tester.tap(find.text('Ownership & OCI metadata'));
    await tester.pumpAndSettle();
    for (final key in [
      'tenancy',
      'region',
      'compartment',
      'resourceId',
      'vcnId',
    ]) {
      expect(field(key).readOnly, isTrue, reason: key);
    }
    expect(field('owner').readOnly, isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('editor-owner')));
    await tester.enterText(
      find.byKey(const ValueKey('editor-owner')),
      'Fictional platform team',
    );
    await tester.ensureVisible(find.text('Save prefix'));
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    final saved = store.list().single;
    expect(saved.owner, 'Fictional platform team');
    expect(saved.source, 'oci');
    expect(saved.cidr, imported.cidr);
    expect(saved.resourceId, imported.resourceId);
    expect(saved.verifiedAt, imported.verifiedAt);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cross-domain parent is rejected inline in the editor', (
    tester,
  ) async {
    controller.loadDemo();
    await workspace(tester);
    await openDetailsEditor(tester, 'Isolated customer VCN');
    await tester.ensureVisible(find.text('No declared parent'));
    await tester.tap(find.text('No declared parent'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('10.64.0.0/16 · Western region allocation').last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save prefix'));
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(find.text('Save prefix'), findsOneWidget);
    expect(
      store.list().singleWhere((r) => r.id == 'demo-isolated').parentId,
      isEmpty,
    );
    expect(
      find.textContaining('must use the same routing domain'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a store failure keeps the editor open with its input', (
    tester,
  ) async {
    await workspace(tester);
    await tester.tap(find.text('New prefix'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-name')),
      'Fictional unsaved VCN',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-cidr')),
      '10.90.0.0/20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-routingDomain')),
      'corporate',
    );
    store.close();
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inventory is closed'), findsOneWidget);
    expect(find.text('Save prefix'), findsOneWidget);
    expect(find.text('Fictional unsaved VCN'), findsOneWidget);
    expect(find.text('10.90.0.0/20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a conflict review keeps the editor open', (
    tester,
  ) async {
    controller.save(
      const PrefixRecord(
        id: 'existing',
        cidr: '10.64.0.0/20',
        name: 'Existing VCN',
        routingDomain: 'corporate',
      ),
    );
    await workspace(tester);
    await tester.tap(find.text('New prefix'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('editor-name')),
      'Overlapping VCN',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-cidr')),
      '10.64.0.0/21',
    );
    await tester.enterText(
      find.byKey(const ValueKey('editor-routingDomain')),
      'corporate',
    );
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Save with conflicts'), findsNothing);
    expect(find.text('Overlapping VCN'), findsOneWidget);
    expect(controller.records.length, 1);
  });

  testWidgets('header import applies OCI discovery and refreshes', (
    tester,
  ) async {
    final client = FakeOciInventoryClient();
    await workspace(tester, ociClient: client);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover from OCI CLI'));
    await tester.pumpAndSettle();
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
    await tester.enterText(
      find.byKey(const ValueKey('oci-domain')),
      'corporate',
    );
    await tester.tap(find.text('Discover inventory'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 network CIDR'), findsOneWidget);
    await tester.tap(find.text('Apply import'));
    await tester.pumpAndSettle();
    expect(controller.records.single.source, 'oci');
    expect(controller.records.single.routingDomain, 'corporate');
    expect(controller.history.first.action, 'import');
    expect(find.text('Build your address map'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  void saveRecords(int count) {
    for (var i = 0; i < count; i++) {
      store.save(
        PrefixRecord(
          id: 'record-$i',
          cidr: '10.${i ~/ 256}.${i % 256}.0/24',
          name: 'Fictional $i',
          routingDomain: 'corporate',
        ),
      );
    }
  }

  testWidgets('exactly 100 changes offer no Load more', (tester) async {
    saveRecords(100);
    controller.refresh();
    expect(controller.history.length, 100);
    expect(controller.hasMoreHistory, isFalse);
    controller.navigate(3);
    await workspace(tester);
    // Scroll to the end of the list, past the oldest entry.
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
    // The oldest change is on screen and nothing follows it.
    expect(
      find.textContaining('Fictional 0 (10.0.0.0/24', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('history-load-more')), findsNothing);
    expect(find.textContaining('Showing the latest'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('101 changes offer Load more for the oldest one', (tester) async {
    saveRecords(101);
    controller.refresh();
    expect(controller.history.length, 100);
    expect(controller.hasMoreHistory, isTrue);
    controller.navigate(3);
    await workspace(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-load-more')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('history-load-more')));
    await tester.pumpAndSettle();
    expect(controller.history.length, 101);
    expect(controller.hasMoreHistory, isFalse);
    expect(find.byKey(const ValueKey('history-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AtlasApp forwards the OCI client factory to discovery', (
    tester,
  ) async {
    final client = FakeOciInventoryClient();
    final collector = FakeOciInventoryClient();
    Duration? requested;
    await workspace(
      tester,
      ociClient: client,
      ociClientFactory: ({Duration? collectionTimeout}) {
        requested = collectionTimeout;
        return collector;
      },
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover from OCI CLI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLI and configuration paths'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('oci-collection-timeout')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('oci-collection-timeout')),
      '30',
    );
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
    await tester.enterText(
      find.byKey(const ValueKey('oci-domain')),
      'corporate',
    );
    await tester.ensureVisible(find.text('Discover inventory'));
    await tester.tap(find.text('Discover inventory'));
    await tester.pumpAndSettle();
    expect(requested, const Duration(minutes: 30));
    expect(collector.requestedCompartment, 'ocid1.compartment.oc1..fictional');
    expect(client.requestedCompartment, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history pages beyond the latest 100 changes', (tester) async {
    for (var i = 0; i < 105; i++) {
      store.save(
        PrefixRecord(
          id: 'record-$i',
          cidr: '10.${i ~/ 256}.${i % 256}.0/24',
          name: 'Fictional $i',
          routingDomain: 'corporate',
        ),
      );
    }
    controller.refresh();
    expect(controller.history.length, 100);
    controller.navigate(3);
    await workspace(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-load-more')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.textContaining('Showing the latest 100 changes'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('history-load-more')));
    await tester.pumpAndSettle();
    expect(controller.history.length, 105);
    expect(find.byKey(const ValueKey('history-load-more')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('record editor shows a non-blocking placeholder-parent notice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const placeholder = PrefixRecord(
      id: 'placeholder-vcn',
      cidr: '10.70.0.0/16',
      name: 'Planned VCN',
      routingDomain: 'example',
    );
    const observed = PrefixRecord(
      id: 'observed-vcn',
      cidr: '10.71.0.0/16',
      name: 'Observed VCN',
      routingDomain: 'example',
      resourceId: 'ocid1.vcn.oc1..fictional',
    );
    const subnet = PrefixRecord(
      id: 'planned-subnet',
      cidr: '10.70.1.0/24',
      name: 'Planned subnet',
      routingDomain: 'example',
      kind: PrefixKind.subnet,
      parentId: 'placeholder-vcn',
      vcnId: 'ocid1.vcn.oc1..fictional',
    );
    PrefixRecord? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordEditor(
            records: const [placeholder, observed, subnet],
            record: subnet,
            onSave: (record) async {
              saved = record;
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final notice = find.byKey(const ValueKey('editor-advisory-0'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('Clear or change the parent'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(saved?.parentId, 'placeholder-vcn');
  });
}
