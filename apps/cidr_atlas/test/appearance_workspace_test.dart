// CIDR Atlas
// Settings dialog, appearance switching and light-mode screen tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:async';

import 'package:cidr_atlas/app.dart';
import 'package:cidr_atlas/appearance.dart';
import 'package:cidr_atlas/controller.dart';
import 'package:cidr_atlas/theme.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:cidr_oci/cidr_oci.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fake_oci_client.dart';

void main() {
  late InventoryStore store;
  late AtlasController controller;
  late InMemorySharedPreferencesAsync preferences;
  late AppearanceController appearance;

  setUp(() async {
    store = InventoryStore.memory();
    controller = AtlasController(store, databasePath: ':memory:');
    // Never the real user defaults: an in-memory platform store.
    preferences = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = preferences;
    appearance = await AppearanceController.load(
      SharedPreferencesAppearanceStore(),
    );
  });
  tearDown(() {
    appearance.dispose();
    controller.dispose();
    store.close();
  });

  Future<String?> stored() => preferences.getString(
    'theme.appearance',
    const SharedPreferencesOptions(),
  );

  Future<void> workspace(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    FakeOciInventoryClient? ociClient,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AtlasApp(
        controller: controller,
        appearance: appearance,
        ociClient: ociClient,
      ),
    );
    await tester.pumpAndSettle();
  }

  ThemeMode appThemeMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  AtlasPalette activePalette(WidgetTester tester) =>
      AtlasPalette.of(tester.element(find.text('CIDR Atlas').first));

  Future<void> pressSettingsShortcut(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('the gear opens Settings with the Appearance choice', (
    tester,
  ) async {
    await workspace(tester, size: const Size(1100, 740));
    expect(find.byTooltip('Settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    for (final label in ['System', 'Light', 'Dark']) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('appearance-selector')),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.textContaining('System follows'), findsOneWidget);
    final selector = tester.widget<SegmentedButton<AppearanceMode>>(
      find.byKey(const ValueKey('appearance-selector')),
    );
    expect(selector.selected, {AppearanceMode.system});
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cmd+, opens Settings once', (tester) async {
    await workspace(tester);
    await pressSettingsShortcut(tester);
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
    await pressSettingsShortcut(tester);
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
  });

  testWidgets('the native Settings menu item opens Settings once', (
    tester,
  ) async {
    await workspace(tester);
    Future<void> menu() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        atlasMenuChannel.name,
        atlasMenuChannel.codec.encodeMethodCall(
          const MethodCall('openSettings'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await menu();
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
    await menu();
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
  });

  testWidgets('choosing a segment switches the theme and persists it', (
    tester,
  ) async {
    await workspace(tester);
    expect(appThemeMode(tester), ThemeMode.system);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(appThemeMode(tester), ThemeMode.dark);
    expect(activePalette(tester), AtlasPalette.dark);
    expect(await stored(), 'dark');

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(appThemeMode(tester), ThemeMode.light);
    expect(activePalette(tester), AtlasPalette.light);
    expect(await stored(), 'light');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(appThemeMode(tester), ThemeMode.system);
    expect(await stored(), 'system');
    // The dialog stays open; the choice applied without closing it.
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('System follows the macOS appearance', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await workspace(tester);
    expect(activePalette(tester), AtlasPalette.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(activePalette(tester), AtlasPalette.light);
  });

  testWidgets('a stored choice applies when the app starts', (tester) async {
    await appearance.setMode(AppearanceMode.dark);
    final restored = await AppearanceController.load(
      SharedPreferencesAppearanceStore(),
    );
    appearance.dispose();
    appearance = restored;
    await workspace(tester);
    expect(appThemeMode(tester), ThemeMode.dark);
    expect(activePalette(tester), AtlasPalette.dark);
  });

  // Light is the new palette; dark repeats the checks for the original look.
  for (final (mode, palette) in [
    (AppearanceMode.light, AtlasPalette.light),
    (AppearanceMode.dark, AtlasPalette.dark),
  ]) {
    for (final size in const [Size(1100, 740), Size(1440, 900)]) {
      group(
        '${mode.name} mode at ${size.width.toInt()}x${size.height.toInt()}',
        () {
          setUp(() => appearance.setMode(mode));

          testWidgets('workspace pages build', (tester) async {
            controller.loadDemo();
            controller.save(
              const PrefixRecord(
                id: 'fictional-overlap',
                cidr: '10.64.0.0/24',
                name: 'Fictional overlap',
                routingDomain: 'demo-corporate',
              ),
              rejectConflicts: false,
            );
            expect(controller.conflicts, isNotEmpty);
            await workspace(tester, size: size);
            expect(activePalette(tester), palette);
            await tester.scrollUntilVisible(
              find.text('Production VCN'),
              200,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.tap(find.text('Production VCN'));
            await tester.pumpAndSettle();
            if (size.width < 1202) {
              await tester.tapAt(const Offset(4, 4));
              await tester.pumpAndSettle();
            }
            for (final page in [
              'Conflicts',
              'Planner',
              'History',
              'Inventory',
            ]) {
              await tester.tap(find.text(page).first);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: page);
            }
            await tester.tap(find.byTooltip('Hierarchy view'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });

          testWidgets('empty inventory builds', (tester) async {
            await workspace(tester, size: size);
            expect(find.text('Build your address map'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });

          testWidgets('planner recommendation builds', (tester) async {
            controller.loadDemo();
            await workspace(tester, size: size);
            await tester.tap(find.text('Planner'));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('planner-domain')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('demo-corporate').last);
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('planner-pool')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.textContaining('Western region allocation').last,
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('planner-calculate')),
            );
            await tester.tap(find.byKey(const ValueKey('planner-calculate')));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('address-map')), findsOneWidget);
            expect(tester.takeException(), isNull);
          });

          testWidgets('record, checker and settings dialogs build', (
            tester,
          ) async {
            await workspace(tester, size: size);
            await tester.tap(find.widgetWithText(FilledButton, 'New prefix'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Cancel').last);
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Can I use this CIDR?'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tapAt(const Offset(4, 4));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Settings'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('settings-dialog')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          });

          testWidgets('import and OCI discovery dialogs build', (tester) async {
            final client = FakeOciInventoryClient()
              ..pending = Completer<OciDiscovery>();
            await workspace(tester, size: size, ociClient: client);
            await tester.tap(find.widgetWithText(OutlinedButton, 'Import'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Discover from OCI CLI'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
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
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(
              find.byKey(const ValueKey('oci-progress-overlay')),
              findsOneWidget,
            );
            final barrier = tester.widget<ModalBarrier>(
              find.descendant(
                of: find.byKey(const ValueKey('oci-progress-overlay')),
                matching: find.byType(ModalBarrier),
              ),
            );
            expect(barrier.color, palette.barrier);
            expect(tester.takeException(), isNull);
            client.pending!.complete(const OciDiscovery(bundleJson: bundle));
            await tester.pumpAndSettle();
            expect(find.textContaining('1 network CIDR'), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        },
      );
    }
  }
}
