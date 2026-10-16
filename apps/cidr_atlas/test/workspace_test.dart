// CIDR Atlas
// Desktop workspace and dialog widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/app.dart';
import 'package:cidr_atlas/controller.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_atlas/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

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
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(AtlasApp(controller: controller));
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
}
