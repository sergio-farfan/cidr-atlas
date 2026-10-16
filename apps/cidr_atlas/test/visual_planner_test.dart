// CIDR Atlas
// Address-space planning, selection, and reservation widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/cidr_inspector.dart';
import 'package:cidr_atlas/visual_planner.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const pool = PrefixRecord(
  id: 'pool',
  cidr: '10.42.0.0/16',
  name: 'Fictional allocation',
  routingDomain: 'corporate',
  kind: PrefixKind.allocation,
);
const vcn = PrefixRecord(
  id: 'vcn',
  cidr: '10.42.0.0/20',
  name: 'Fictional VCN',
  routingDomain: 'corporate',
  kind: PrefixKind.vcn,
  parentId: 'pool',
  resourceId: 'ocid1.vcn.fictional',
  tenancy: 'fictional',
  region: 'fictional-west',
);

void main() {
  Future<void> showPlanner(
    WidgetTester tester, {
    List<PrefixRecord> records = const [pool, vcn],
    void Function(PrefixRecord)? onReserve,
    Size size = const Size(1100, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: VisualPlanner(records: records, onReserve: onReserve ?? (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String key, String text) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> plan(
    WidgetTester tester, {
    String selectedPool = 'Fictional allocation (10.42.0.0/16)',
  }) async {
    await select(tester, 'planner-domain', 'corporate');
    await select(tester, 'planner-pool', selectedPool);
    await tester.ensureVisible(find.byKey(const ValueKey('planner-calculate')));
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
  }

  testWidgets('planning requires an explicit routing domain', (tester) async {
    await showPlanner(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('planner-calculate')));
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a routing domain'), findsWidgets);
    expect(find.byKey(const ValueKey('reserve-candidate')), findsNothing);
  });
  for (final size in [const Size(1100, 740), const Size(1440, 900)]) {
    testWidgets('exact bounded planning and responsive selection at $size', (
      tester,
    ) async {
      PrefixRecord? reserved;
      await showPlanner(tester, size: size, onReserve: (r) => reserved = r);
      await plan(tester);
      expect(find.text('12 shown of 240 candidates'), findsOneWidget);
      expect(find.text('Available in this inventory'), findsWidgets);
      expect(find.textContaining('61,440'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('candidate-0')));
      await tester.tap(find.byKey(const ValueKey('candidate-0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('reserve-candidate')),
      );
      await tester.tap(find.byKey(const ValueKey('reserve-candidate')));
      await tester.pumpAndSettle();
      expect(reserved, isNotNull);
      expect(reserved!.parentId, pool.id);
      expect(reserved!.kind, PrefixKind.vcn);
      expect(reserved!.status, PrefixStatus.reserved);
      expect(reserved!.routingDomain, 'corporate');
      expect(reserved!.notes, contains('inventory'));
      expect(InventoryRules.validate([pool, vcn, reserved!]), isEmpty);
      expect(InventoryRules.conflicts([pool, vcn, reserved!]), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('desktop map and inspector share the first planning viewport', (
    tester,
  ) async {
    await showPlanner(tester, size: const Size(1440, 900));
    await plan(tester);
    final map = tester.getRect(find.byType(InteractiveViewer));
    final mapTitle = tester.getRect(find.text('Ordered address map'));
    final inputs = tester.getRect(find.byKey(const ValueKey('planner-domain')));
    final inspector = tester.getRect(find.byType(CidrInspector));
    expect(mapTitle.top, lessThan(350));
    expect(map.width, greaterThanOrEqualTo(600));
    expect(inputs.right, lessThan(map.left));
    expect(inspector.left, greaterThan(map.right));
    expect(inspector.top, lessThan(300));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 700), const Size(780, 650)]) {
    testWidgets(
      'small-window planning scrolls through inputs to reservation at $size',
      (tester) async {
        PrefixRecord? reserved;
        await showPlanner(
          tester,
          size: size,
          onReserve: (record) => reserved = record,
        );
        await plan(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('candidate-1')));
        await tester.tap(find.byKey(const ValueKey('candidate-1')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('reserve-candidate')),
        );
        await tester.tap(find.byKey(const ValueKey('reserve-candidate')));
        expect(reserved?.cidr, '10.42.31.0/24');
        expect(reserved?.parentId, pool.id);
        expect(InventoryRules.conflicts([pool, vcn, reserved!]), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('input edits invalidate selected candidates before reservation', (
    tester,
  ) async {
    await showPlanner(tester);
    await plan(tester);
    expect(find.byKey(const ValueKey('candidate-0')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('planner-prefix')));
    await tester.enterText(find.byKey(const ValueKey('planner-prefix')), '25');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('candidate-0')), findsNothing);
    expect(find.byKey(const ValueKey('reserve-candidate')), findsNothing);
  });
  testWidgets('inventory changes and pool retirement invalidate a plan', (
    tester,
  ) async {
    final records = ValueNotifier<List<PrefixRecord>>([pool, vcn]);
    addTearDown(records.dispose);
    tester.view.physicalSize = const Size(1100, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: records,
            builder: (_, rows, _) =>
                VisualPlanner(records: rows, onReserve: (_) {}),
          ),
        ),
      ),
    );
    await plan(tester);
    records.value = [pool.copyWith(status: PrefixStatus.retired), vcn];
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('candidate-0')), findsNothing);
    expect(find.text('Enter a range manually'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'demand exposes explicit growth and extra demand and preserves rationale',
    (tester) async {
      PrefixRecord? reserved;
      await showPlanner(tester, onReserve: (r) => reserved = r);
      await select(tester, 'planner-domain', 'corporate');
      await select(tester, 'planner-pool', 'Fictional VCN (10.42.0.0/20)');
      await select(tester, 'planner-mode', 'Size from address demand');
      expect(find.byKey(const ValueKey('planner-growth')), findsOneWidget);
      expect(find.byKey(const ValueKey('planner-additional')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('planner-demand')),
        '100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('planner-growth')),
        '20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('planner-additional')),
        '4',
      );
      await select(tester, 'planner-basis', 'Already planned peak');
      await tester.ensureVisible(
        find.byKey(const ValueKey('planner-calculate')),
      );
      await tester.tap(find.byKey(const ValueKey('planner-calculate')));
      await tester.pumpAndSettle();
      expect(find.textContaining('124 planned'), findsWidgets);
      expect(find.textContaining('125 assignable'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const ValueKey('reserve-candidate')),
      );
      await tester.tap(find.byKey(const ValueKey('reserve-candidate')));
      expect(reserved!.kind, PrefixKind.subnet);
      expect(reserved!.vcnId, vcn.resourceId);
      expect(reserved!.notes, contains('100'));
      expect(reserved!.notes, contains('20'));
      expect(reserved!.notes, contains('4'));
      expect(reserved!.notes.toLowerCase(), contains('peak'));
    },
  );
  testWidgets('OCI subnet policy rejects a generic slash 31', (tester) async {
    await showPlanner(tester);
    await select(tester, 'planner-domain', 'corporate');
    await select(tester, 'planner-pool', 'Fictional VCN (10.42.0.0/20)');
    await select(tester, 'planner-policy', 'OCI IPv4 subnet');
    await tester.enterText(find.byKey(const ValueKey('planner-prefix')), '31');
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
    expect(find.textContaining('/16 through /30'), findsWidgets);
    expect(find.byKey(const ValueKey('candidate-0')), findsNothing);
  });
  testWidgets('partial slots block and overlapping records display conflicts', (
    tester,
  ) async {
    await showPlanner(
      tester,
      records: [
        pool.copyWith(cidr: '10.42.0.0/24'),
        const PrefixRecord(
          id: 'a',
          cidr: '10.42.0.0/26',
          name: 'Partial blocker',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        const PrefixRecord(
          id: 'b',
          cidr: '10.42.0.32/27',
          name: 'Conflicting observation',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
      ],
    );
    await select(tester, 'planner-domain', 'corporate');
    await select(tester, 'planner-pool', 'Fictional allocation (10.42.0.0/24)');
    await tester.enterText(find.byKey(const ValueKey('planner-prefix')), '25');
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
    expect(find.text('1 shown of 1 candidates'), findsOneWidget);
    expect(find.textContaining('Conflict'), findsWidgets);
    expect(find.textContaining('Blocked'), findsWidgets);
    expect(find.text('10.42.0.128/25'), findsWidgets);
  });
  testWidgets('large IPv6 counts stay exact and keyboard selects candidate', (
    tester,
  ) async {
    await showPlanner(tester, records: [pool.copyWith(cidr: '::/0')]);
    await select(tester, 'planner-domain', 'corporate');
    await select(tester, 'planner-pool', 'Fictional allocation (::/0)');
    await tester.enterText(find.byKey(const ValueKey('planner-prefix')), '64');
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
    expect(
      find.text('12 shown of 18446744073709551616 candidates'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('candidate-1')));
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('candidate-1')),
    );
    button.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected candidate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('map zoom persists across selection and resets explicitly', (
    tester,
  ) async {
    await showPlanner(tester);
    await plan(tester);
    await tester.ensureVisible(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('candidate-1')));
    await tester.tap(find.byKey(const ValueKey('candidate-1')));
    await tester.pump();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tester.ensureVisible(find.byTooltip('Reset view'));
    await tester.tap(find.byTooltip('Reset view'));
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
  });
  testWidgets(
    'one OCI resource groups CIDRs while unresolved context stays visible',
    (tester) async {
      await showPlanner(
        tester,
        records: [
          pool,
          vcn,
          vcn.copyWith(id: 'vcn6', cidr: '2001:db8::/48', parentId: ''),
          const PrefixRecord(
            id: 'orphan',
            cidr: '192.0.2.0/24',
            name: 'Unresolved subnet',
            routingDomain: 'corporate',
            kind: PrefixKind.subnet,
            vcnId: 'ocid1.vcn.missing',
            tenancy: 'fictional',
            region: 'fictional-west',
          ),
        ],
      );
      await select(tester, 'planner-domain', 'corporate');
      expect(
        find.byKey(
          const ValueKey(
            'resource-vcn:corporate:fictional:fictional-west:ocid1.vcn.fictional',
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2 CIDRs'), findsOneWidget);
      expect(find.textContaining('Unresolved VCN context'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'same OCI identity in separate domains retains separate hierarchy groups',
    (tester) async {
      await showPlanner(
        tester,
        records: [
          vcn.copyWith(parentId: ''),
          vcn.copyWith(
            id: 'vcn-separated',
            parentId: '',
            routingDomain: 'isolated',
          ),
        ],
      );
      expect(find.text('Fictional VCN'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('nested allocation ancestry remains explicit and resolved', (
    tester,
  ) async {
    await showPlanner(
      tester,
      records: [
        pool,
        pool.copyWith(
          id: 'regional',
          name: 'Fictional regional allocation',
          cidr: '10.42.0.0/20',
          parentId: pool.id,
        ),
      ],
    );
    expect(find.textContaining('Unresolved explicit parent'), findsNothing);
    expect(find.text('Fictional regional allocation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid OCI explicit membership is shown as unresolved', (
    tester,
  ) async {
    await showPlanner(
      tester,
      records: [
        vcn.copyWith(parentId: ''),
        const PrefixRecord(
          id: 'wrong-context',
          cidr: '10.42.0.0/24',
          name: 'Fictional mismatched subnet',
          routingDomain: 'corporate',
          kind: PrefixKind.subnet,
          parentId: 'vcn',
          tenancy: 'another-fictional-tenancy',
          region: 'fictional-west',
        ),
      ],
    );
    expect(find.textContaining('Unresolved explicit parent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('observed OCI subnet selection shows provider capacity', (
    tester,
  ) async {
    await showPlanner(
      tester,
      records: const [
        PrefixRecord(
          id: 'observed-subnet',
          cidr: '10.42.0.0/24',
          name: 'Fictional observed subnet',
          routingDomain: 'corporate',
          kind: PrefixKind.subnet,
          source: 'oci',
        ),
      ],
    );
    await tester.ensureVisible(find.text('10.42.0.0/24'));
    await tester.tap(find.text('10.42.0.0/24'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Inspect 10.42.0.0/24'));
    await tester.tap(find.text('Inspect 10.42.0.0/24'));
    await tester.pumpAndSettle();
    expect(find.text('253 assignable addresses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inspector reports exact IPv6 and does not invent provider capacity',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CidrInspector(cidr: Cidr.parse('::/0')),
            ),
          ),
        ),
      );
      expect(
        find.text('340,282,366,920,938,463,463,374,607,431,768,211,456'),
        findsOneWidget,
      );
      expect(find.text('Subnet mask'), findsNothing);
      expect(find.textContaining('128 host bits'), findsOneWidget);
      expect(find.text('IPv6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
