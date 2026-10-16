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
    // The strict failure is shown inside the still-open editor.
    expect(find.textContaining('Allocation conflicts'), findsOneWidget);
    expect(find.text('Save prefix'), findsOneWidget);
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
    // The edited value is kept for review instead of being discarded.
    expect(find.text('10.64.9.0/24'), findsOneWidget);
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

  group('planner reservation end to end', () {
    Future<void> planInDemoVcn(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      controller.navigate(2);
      await tester.pumpWidget(AtlasApp(controller: controller));
      await tester.pumpAndSettle();
      Future<void> select(String key, String text) async {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      await select('planner-domain', 'demo-corporate');
      await select('planner-pool', 'Production VCN (10.64.0.0/20)');
      await select('planner-policy', 'OCI IPv4 subnet');
      await tester.ensureVisible(
        find.byKey(const ValueKey('planner-calculate')),
      );
      await tester.tap(find.byKey(const ValueKey('planner-calculate')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('reserve-candidate')),
      );
    }

    testWidgets('a planner candidate is reserved strictly through the editor', (
      tester,
    ) async {
      await planInDemoVcn(tester);
      final rationale = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data ?? '')
          .firstWhere((text) => text.contains('Policy: ociIpv4Subnet'));
      await tester.tap(find.byKey(const ValueKey('reserve-candidate')));
      await tester.pumpAndSettle();
      expect(find.text('New prefix'), findsWidgets);
      await tester.ensureVisible(find.text('Save prefix'));
      await tester.tap(find.text('Save prefix'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recalculate'), findsNothing);
      expect(store.list().length, 7);
      final saved = store.list().singleWhere(
        (record) => record.id.startsWith('reservation-'),
      );
      expect(saved.source, 'planner');
      expect(saved.kind, PrefixKind.subnet);
      expect(saved.status, PrefixStatus.reserved);
      expect(saved.parentId, 'demo-vcn');
      expect(saved.vcnId, 'demo-vcn-resource');
      expect(saved.tenancy, 'demo-tenancy');
      expect(saved.notes, contains(rationale));
      expect(InventoryRules.conflicts(store.list()), isEmpty);
      expect(store.history().first.action, 'reserve');

      // The saved OCI subnet keeps the capacity its rationale cites.
      controller.navigate(0);
      await tester.pumpAndSettle();
      controller.select(saved.id);
      await tester.pumpAndSettle();
      expect(find.text('PREFIX DETAILS'), findsOneWidget);
      expect(find.text('253 assignable addresses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a concurrent conflicting save fails without an override', (
      tester,
    ) async {
      await planInDemoVcn(tester);
      final cidr = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('candidate-0')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      await tester.tap(find.byKey(const ValueKey('reserve-candidate')));
      await tester.pumpAndSettle();
      // Another process (cidrctl) takes the same range meanwhile.
      store.save(
        PrefixRecord(
          id: 'other-process',
          cidr: cidr,
          name: 'Concurrent reservation',
          routingDomain: 'demo-corporate',
          kind: PrefixKind.subnet,
          parentId: 'demo-vcn',
          tenancy: 'demo-tenancy',
          region: 'us-phoenix-1',
          vcnId: 'demo-vcn-resource',
        ),
      );
      await tester.ensureVisible(find.text('Save prefix'));
      await tester.tap(find.text('Save prefix'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allocation conflicts'), findsOneWidget);
      expect(find.text('Save with conflicts'), findsNothing);
      expect(
        store.list().where((record) => record.id.startsWith('reservation-')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
