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

  testWidgets('compact desktop keeps inputs beside a scroll-accessible map', (
    tester,
  ) async {
    // A 1100x750 app leaves this space after its sidebar, header and footer.
    await showPlanner(tester, size: const Size(898, 576));
    await plan(tester);
    await tester.ensureVisible(find.byType(InteractiveViewer));
    await tester.pumpAndSettle();
    final map = tester.getRect(find.byType(InteractiveViewer));
    final inputs = tester.getRect(find.byKey(const ValueKey('planner-domain')));
    expect(inputs.right, lessThan(map.left));
    expect(map.width, greaterThanOrEqualTo(500));
    expect(map.top, greaterThanOrEqualTo(0));
    expect(map.bottom, lessThanOrEqualTo(576));
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

  group('planner input validation', () {
    const smallVcn = PrefixRecord(
      id: 'small-vcn',
      cidr: '10.42.0.0/26',
      name: 'Fictional small VCN',
      routingDomain: 'corporate',
      kind: PrefixKind.vcn,
      resourceId: 'ocid1.vcn.small',
    );

    Future<void> calculate(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('planner-calculate')),
      );
      await tester.tap(find.byKey(const ValueKey('planner-calculate')));
      await tester.pumpAndSettle();
    }

    void expectReadable(WidgetTester tester, String message) {
      expect(find.textContaining(message), findsOneWidget);
      expect(find.textContaining('RangeError'), findsNothing);
      expect(find.textContaining('Invalid argument'), findsNothing);
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.byKey(const ValueKey('reserve-candidate')), findsNothing);
      expect(tester.takeException(), isNull);
    }

    testWidgets('a prefix shorter than the pool explains the valid range', (
      tester,
    ) async {
      await showPlanner(tester, records: const [smallVcn]);
      await select(tester, 'planner-domain', 'corporate');
      await select(
        tester,
        'planner-pool',
        'Fictional small VCN (10.42.0.0/26)',
      );
      await calculate(tester);
      expectReadable(
        tester,
        'Requested /24 does not fit the /26 pool 10.42.0.0/26; '
        'choose /26 to /32.',
      );
    });

    testWidgets('a prefix longer than the address family is rejected', (
      tester,
    ) async {
      await showPlanner(tester);
      await select(tester, 'planner-domain', 'corporate');
      await select(
        tester,
        'planner-pool',
        'Fictional allocation (10.42.0.0/16)',
      );
      await tester.enterText(
        find.byKey(const ValueKey('planner-prefix')),
        '40',
      );
      await calculate(tester);
      expectReadable(tester, 'choose /16 to /32.');
    });

    for (final (field, value, message) in [
      ('planner-demand', '0', 'Endpoint IP demand must be at least 1'),
      ('planner-growth', '-5', 'growth allowance cannot be negative'),
      ('planner-additional', '-1', 'cannot be negative; enter 0 if none'),
    ]) {
      testWidgets('demand field $field=$value shows a readable message', (
        tester,
      ) async {
        await showPlanner(tester, records: [pool, vcn]);
        await select(tester, 'planner-domain', 'corporate');
        await select(tester, 'planner-pool', 'Fictional VCN (10.42.0.0/20)');
        await select(tester, 'planner-mode', 'Size from address demand');
        await tester.enterText(
          find.byKey(const ValueKey('planner-demand')),
          '100',
        );
        await tester.enterText(
          find.byKey(const ValueKey('planner-growth')),
          '10',
        );
        await tester.enterText(find.byKey(ValueKey(field)), value);
        await calculate(tester);
        expectReadable(tester, message);
      });
    }
  });

  testWidgets('narrow free gaps are painted above blocked space', (
    tester,
  ) async {
    // One /28 hole in an otherwise blocked /16: under 1 px at map width.
    await showPlanner(
      tester,
      records: const [
        pool,
        PrefixRecord(
          id: 'low',
          cidr: '10.42.0.0/17',
          name: 'Fictional low half',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour',
          cidr: '10.42.128.16/28',
          name: 'Fictional neighbour',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-2',
          cidr: '10.42.128.32/27',
          name: 'Fictional neighbour 2',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-3',
          cidr: '10.42.128.64/26',
          name: 'Fictional neighbour 3',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-4',
          cidr: '10.42.128.128/25',
          name: 'Fictional neighbour 4',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-5',
          cidr: '10.42.129.0/24',
          name: 'Fictional neighbour 5',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-6',
          cidr: '10.42.130.0/23',
          name: 'Fictional neighbour 6',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-7',
          cidr: '10.42.132.0/22',
          name: 'Fictional neighbour 7',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-8',
          cidr: '10.42.136.0/21',
          name: 'Fictional neighbour 8',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'gap-neighbour-9',
          cidr: '10.42.144.0/20',
          name: 'Fictional neighbour 9',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'high',
          cidr: '10.42.160.0/19',
          name: 'Fictional high block',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
        PrefixRecord(
          id: 'top',
          cidr: '10.42.192.0/18',
          name: 'Fictional top block',
          routingDomain: 'corporate',
          parentId: 'pool',
        ),
      ],
    );
    await select(tester, 'planner-domain', 'corporate');
    await select(tester, 'planner-pool', 'Fictional allocation (10.42.0.0/16)');
    await tester.enterText(find.byKey(const ValueKey('planner-prefix')), '28');
    await tester.ensureVisible(find.byKey(const ValueKey('planner-calculate')));
    await tester.tap(find.byKey(const ValueKey('planner-calculate')));
    await tester.pumpAndSettle();
    expect(find.text('10.42.128.0/28'), findsWidgets);

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('address-map')),
    );
    final size = tester.getSize(find.byKey(const ValueKey('address-map')));
    final canvas = _RecordingCanvas();
    paint.painter!.paint(canvas, size);
    bool freeColor(Color color) => color.toARGB32() & 0xffffff == 0x77d8b4;
    bool blockedColor(Color color) => color.toARGB32() & 0xffffff == 0xdbc18b;
    final lastBlocked = canvas.rects.lastIndexWhere(
      (entry) => blockedColor(entry.$2),
    );
    final free = canvas.rects.indexWhere((entry) => freeColor(entry.$2));
    expect(lastBlocked, greaterThanOrEqualTo(0));
    expect(free, greaterThan(lastBlocked));
    final marker = canvas.rects[free];
    expect(marker.$1.width, greaterThanOrEqualTo(2));
    expect(marker.$2.a, greaterThan(0.9));
    expect(tester.takeException(), isNull);
  });

  group('address map zoom', () {
    double candidateCentre(WidgetTester tester, double width) {
      final text = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('candidate-0')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      final cidr = Cidr.parse(text);
      final parent = Cidr.parse('10.42.0.0/16');
      double x(BigInt address) =>
          ((address - parent.networkAddress).toDouble() /
                  parent.addressCount.toDouble() *
                  width)
              .clamp(0, width);
      final start = x(cidr.networkAddress);
      final w = x(cidr.lastAddress + BigInt.one) - start;
      final rectWidth = w < 4 ? 4.0 : w;
      final left = start < width - rectWidth ? start : width - rectWidth;
      return left + rectWidth / 2;
    }

    testWidgets('zoom keeps the selected candidate at its screen position', (
      tester,
    ) async {
      await showPlanner(tester, size: const Size(1440, 900));
      await plan(tester);
      final width = tester.getSize(find.byType(InteractiveViewer)).width;
      final centre = candidateCentre(tester, width);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      await tester.ensureVisible(find.byTooltip('Zoom in'));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      final matrix = viewer.transformationController!.value;
      expect(matrix.entry(0, 0), closeTo(1.5, 1e-9));
      // The address axis is magnified; the bar keeps its height.
      expect(matrix.entry(1, 1), 1);
      final transformed = matrix.entry(0, 0) * centre + matrix.entry(0, 3);
      expect(transformed, closeTo(centre, 1));
      // Panning the axis-only magnification stays within the viewer.
      await tester.drag(find.byType(InteractiveViewer), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('zoom to candidate centres it and replaces the Fit duplicate', (
      tester,
    ) async {
      await showPlanner(tester, size: const Size(1440, 900));
      await plan(tester);
      expect(find.text('Fit'), findsNothing);
      final width = tester.getSize(find.byType(InteractiveViewer)).width;
      final centre = candidateCentre(tester, width);
      await tester.ensureVisible(
        find.byKey(const ValueKey('map-zoom-candidate')),
      );
      await tester.tap(find.byKey(const ValueKey('map-zoom-candidate')));
      await tester.pump();
      final matrix = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value;
      final scale = matrix.entry(0, 0);
      expect(scale, greaterThan(1.5));
      final transformed = scale * centre + matrix.entry(0, 3);
      expect(transformed, greaterThanOrEqualTo(0));
      expect(transformed, lessThanOrEqualTo(width));
      // Centred unless the view is clamped at the end of the address space.
      final clampedAtEdge =
          matrix.entry(0, 3).abs() < 1e-6 ||
          (matrix.entry(0, 3) - (width - scale * width)).abs() < 1e-6;
      if (!clampedAtEdge) expect(transformed, closeTo(width / 2, 1));
      await tester.tap(find.byTooltip('Reset view'));
      await tester.pump();
      expect(matrix.getMaxScaleOnAxis(), isNot(1));
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        1,
      );
    });
  });

  testWidgets('candidate selection is exposed to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await showPlanner(tester);
    await plan(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('candidate-1')));
    await tester.tap(find.byKey(const ValueKey('candidate-1')));
    await tester.pumpAndSettle();
    final selected = tester.getSemantics(
      find.byKey(const ValueKey('candidate-1')),
    );
    expect(selected, isSemantics(isSelected: true, isButton: true));
    expect(selected.label, contains('Candidate 2 of 12'));
    expect(
      tester.getSemantics(find.byKey(const ValueKey('candidate-0'))),
      isNot(isSemantics(isSelected: true)),
    );
    semantics.dispose();
  });

  testWidgets('supplied conflicts mark the hierarchy without a rescan', (
    tester,
  ) async {
    // The planner trusts the controller's conflicts for this inventory.
    const records = [pool, vcn];
    tester.view.physicalSize = const Size(1100, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualPlanner(
            records: records,
            conflicts: [
              Conflict(first: pool, second: vcn, reason: 'Fictional conflict'),
            ],
            onReserve: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Conflict: overlapping records'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results survive rebuilds until the inventory list changes', (
    tester,
  ) async {
    final records = [pool, vcn];
    var list = records;
    late StateSetter rebuild;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return VisualPlanner(records: list, onReserve: (_) {});
            },
          ),
        ),
      ),
    );
    await plan(tester);
    expect(find.byKey(const ValueKey('reserve-candidate')), findsOneWidget);
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reserve-candidate')), findsOneWidget);
    rebuild(() => list = [...records]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reserve-candidate')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Records rectangles drawn by a painter, ignoring every other call.
class _RecordingCanvas implements Canvas {
  final rects = <(Rect, Color)>[];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
