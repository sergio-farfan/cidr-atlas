// CIDR Atlas
// Planner reservation review and transaction-time conflict integration tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/app.dart';
import 'package:cidr_atlas/controller.dart';
import 'package:cidr_atlas/visual_planner.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InventoryStore store;
  late AtlasController controller;
  const proposal = PrefixRecord(
    id: 'fictional-recommendation',
    cidr: '10.64.8.0/24',
    name: 'Proposed subnet',
    routingDomain: 'demo-corporate',
    kind: PrefixKind.subnet,
    parentId: 'demo-vcn',
    tenancy: 'demo-tenancy',
    region: 'us-phoenix-1',
    vcnId: 'demo-vcn-resource',
    source: 'planner',
    notes: 'Planning decision: 124 required addresses including growth; OCI policy.',
  );

  setUp(() {
    store = InventoryStore.memory();
    controller = AtlasController(store, databasePath: ':memory:')..loadDemo();
  });
  tearDown(() {
    controller.dispose();
    store.close();
  });

  Future<void> openReview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.navigate(2);
    await tester.pumpWidget(AtlasApp(controller: controller));
    await tester.pumpAndSettle();
    tester
        .widget<VisualPlanner>(find.byType(VisualPlanner))
        .onReserve(proposal);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reviewed recommendation saves strictly and retains its decision',
    (tester) async {
      await openReview(tester);
      await tester.enterText(
        find.byKey(const ValueKey('editor-notes')),
        'Reviewed by owner.',
      );
      await tester.tap(find.text('Save prefix'));
      await tester.pumpAndSettle();
      final saved = store.list().singleWhere(
        (record) => record.id == proposal.id,
      );
      expect(saved.notes, contains('Reviewed by owner.'));
      expect(saved.notes, contains(proposal.notes));
      expect(InventoryRules.conflicts(store.list()), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale recommendation cannot use manual conflict override', (
    tester,
  ) async {
    await openReview(tester);
    store.save(
      proposal.copyWith(id: 'other-process', name: 'Concurrent reservation'),
    );
    final history = store.history().length;
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(find.text('Could not complete the change'), findsOneWidget);
    expect(find.text('Save with conflicts'), findsNothing);
    expect(store.list().any((record) => record.id == proposal.id), isFalse);
    expect(store.history().length, history);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing the recommended network requires recalculation', (
    tester,
  ) async {
    await openReview(tester);
    await tester.enterText(
      find.byKey(const ValueKey('editor-cidr')),
      '10.64.9.0/24',
    );
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recalculate'), findsWidgets);
    expect(store.list().any((record) => record.id == proposal.id), isFalse);
  });

  testWidgets('review cannot attach an unobserved OCI resource identity', (
    tester,
  ) async {
    await openReview(tester);
    await tester.ensureVisible(find.text('Ownership & OCI metadata'));
    await tester.tap(find.text('Ownership & OCI metadata'));
    await tester.pumpAndSettle();
    final identity = find.byKey(const ValueKey('editor-resourceId'));
    await tester.ensureVisible(identity);
    await tester.enterText(identity, 'fictional-new-resource');
    await tester.ensureVisible(find.text('Save prefix'));
    await tester.tap(find.text('Save prefix'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recalculate'), findsWidgets);
    expect(store.list().any((record) => record.id == proposal.id), isFalse);
  });
}
