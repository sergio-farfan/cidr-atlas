// CIDR Atlas
// Shared CIDR inspector policy, supernet, and clipboard widget tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/cidr_inspector.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> inspect(
    WidgetTester tester,
    String cidr, {
    AddressPolicy policy = AddressPolicy.generic,
  }) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CidrInspector(cidr: Cidr.parse(cidr), policy: policy),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('OCI details distinguish raw count and reserved address policy', (
    tester,
  ) async {
    await inspect(tester, '10.42.0.0/25', policy: AddressPolicy.ociIpv4Subnet);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('125 assignable addresses'), findsOneWidget);
    expect(find.text('255.255.255.128'), findsOneWidget);
    expect(find.text('10.42.0.2\n10.42.0.126'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generic slash31 retains exact count and can copy canonical CIDR',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await inspect(tester, '192.0.2.0/31');
      expect(find.text('2'), findsWidgets);
      expect(find.text('Provider capacity'), findsNothing);
      await tester.tap(find.byTooltip('Copy Network prefix'));
      await tester.pump();
      expect(copied, '192.0.2.0/31');
    },
  );

  testWidgets(
    'containing supernet is explicit and does not authorize allocation',
    (tester) async {
      await inspect(tester, '10.42.0.128/25');
      await tester.ensureVisible(
        find.byKey(const ValueKey('inspector-supernet-10.42.0.128/25')),
      );
      await tester.tap(
        find.byKey(const ValueKey('inspector-supernet-10.42.0.128/25')),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('/24'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('/24').last);
      await tester.pumpAndSettle();
      expect(find.text('10.42.0.0/24'), findsOneWidget);
      expect(find.textContaining('does not authorize'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
