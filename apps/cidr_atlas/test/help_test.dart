// CIDR Atlas
// Contextual help navigation, clipboard examples, and dialog lifecycle tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/help.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openHelp(
    WidgetTester tester, {
    HelpTopic topic = HelpTopic.gettingStarted,
    Size size = const Size(1100, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAtlasHelp(context, topic: topic),
              child: const Text('Open help'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open help'));
    await tester.pumpAndSettle();
  }

  testWidgets('topic navigation changes the selected guide', (tester) async {
    await openHelp(tester);
    expect(find.text('Where do I enter a prefix?'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('help-topic-imports')));
    await tester.pumpAndSettle();
    expect(find.text('Import files'), findsOneWidget);
    expect(find.text('Where do I enter a prefix?'), findsNothing);
    final selected = tester.widget<ListTile>(
      find.byKey(const ValueKey('help-topic-imports')),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('contextual initial topic opens its guide directly', (
    tester,
  ) async {
    await openHelp(tester, topic: HelpTopic.planning);
    expect(find.text('Plan a new range'), findsOneWidget);
    expect(find.text('Where do I enter a prefix?'), findsNothing);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('help-topic-planning')))
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'discovery guide explains broad scopes, IAM and one combined preview',
    (tester) async {
      await openHelp(tester, topic: HelpTopic.ociDiscovery);
      expect(
        find.textContaining('All READY subscribed regions'),
        findsOneWidget,
      );
      expect(
        find.textContaining('All accessible compartments and subcompartments'),
        findsOneWidget,
      );
      expect(find.textContaining('IAM-hidden'), findsOneWidget);
      expect(find.textContaining('one combined preview'), findsOneWidget);
      expect(
        find.textContaining('Discover each intended child separately'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy exports a usable fictional CSV example', (tester) async {
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
    await openHelp(tester, topic: HelpTopic.imports);
    final copy = find.byTooltip('Copy CSV example');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    final preview = InventoryImport.csv(copied!);
    expect(preview.canApply, isTrue);
    expect(preview.records.single.cidr, '10.64.0.0/16');
    expect(preview.records.single.routingDomain, 'fictional-isolated');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('copy exports a restorable JSON backup example', (tester) async {
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
    await openHelp(tester, topic: HelpTopic.imports);
    final copy = find.byTooltip('Copy JSON backup example');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    final preview = InventoryImport.json(copied!, routingDomain: 'unused');
    expect(preview.canApply, isTrue);
    expect(preview.records.single.cidr, '10.64.0.0/16');
    expect(preview.records.single.routingDomain, 'fictional-isolated');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('CLI import copies explicit file and apply arguments', (
    tester,
  ) async {
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
    await openHelp(tester);
    await tester.tap(find.byKey(const ValueKey('help-topic-cli')));
    await tester.pumpAndSettle();
    final preview = find.byTooltip('Copy CLI import preview');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(
      copied,
      'cidrctl --db fictional.sqlite import csv --file fictional.csv',
    );
    final apply = find.byTooltip('Copy CLI import apply');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(
      copied,
      'cidrctl --db fictional.sqlite import csv --file fictional.csv --apply',
    );
  });

  for (final size in [const Size(1100, 740), const Size(1440, 900)]) {
    testWidgets('all topics fit and scroll at ${size.width}×${size.height}', (
      tester,
    ) async {
      await openHelp(tester, size: size);
      for (final topic in HelpTopic.values) {
        await tester.tap(find.byKey(ValueKey('help-topic-${topic.name}')));
        await tester.pumpAndSettle();
        final scroll = find.byKey(const ValueKey('help-content-scroll'));
        await tester.drag(scroll, const Offset(0, -1800));
        await tester.pumpAndSettle();
        expect(find.text('Close help').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('narrow help uses an accessible topic selector', (tester) async {
    await openHelp(tester, size: const Size(760, 650));
    final selector = find.byKey(const ValueKey('help-topic-selector'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCI discovery').last);
    await tester.pumpAndSettle();
    expect(find.text('Discover existing OCI CIDRs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing nested help preserves its parent dialog input', (
    tester,
  ) async {
    final input = TextEditingController(text: 'fictional-connected');
    addTearDown(input.dispose);
    var helpClosed = false;
    tester.view.physicalSize = const Size(1100, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Import state'),
                  content: TextField(controller: input),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await showAtlasHelp(
                          dialogContext,
                          topic: HelpTopic.imports,
                        );
                        helpClosed = true;
                      },
                      child: const Text('Read import help'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open import'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'fictional-revised');
    await tester.tap(find.text('Read import help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close help'));
    await tester.pumpAndSettle();
    expect(helpClosed, isTrue);
    expect(find.byType(AtlasHelpDialog), findsNothing);
    expect(find.text('Import state'), findsOneWidget);
    expect(find.text('fictional-revised'), findsOneWidget);
    expect(input.text, 'fictional-revised');
    expect(tester.takeException(), isNull);
  });
}
