// CIDR Atlas
// Appearance preference, persistence, palette and contrast tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/appearance.dart';
import 'package:cidr_atlas/main.dart';
import 'package:cidr_atlas/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A store whose reads and writes fail, as an unavailable preference store.
class _FailingStore implements AppearanceStore {
  @override
  Future<String?> read() => Future.error(StateError('unavailable'));
  @override
  Future<void> write(String value) => Future.error(StateError('read-only'));
}

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppearanceMode', () {
    test('labels and theme modes are System, Light and Dark', () {
      expect(AppearanceMode.values.map((m) => m.label), [
        'System',
        'Light',
        'Dark',
      ]);
      expect(AppearanceMode.values.map((m) => m.themeMode), [
        ThemeMode.system,
        ThemeMode.light,
        ThemeMode.dark,
      ]);
      expect(AppearanceMode.values.map((m) => m.storageValue), [
        'system',
        'light',
        'dark',
      ]);
    });

    test('stored values parse; missing or unknown values fall back', () {
      expect(AppearanceMode.parse('system'), AppearanceMode.system);
      expect(AppearanceMode.parse('light'), AppearanceMode.light);
      expect(AppearanceMode.parse('dark'), AppearanceMode.dark);
      for (final value in [null, '', 'Dark', 'sepia', ' light']) {
        expect(
          AppearanceMode.parse(value),
          AppearanceMode.system,
          reason: '$value',
        );
      }
    });
  });

  group('persistence', () {
    late InMemorySharedPreferencesAsync platform;
    const options = SharedPreferencesOptions();

    setUp(() {
      // Never the real user defaults: an in-memory platform store.
      platform = InMemorySharedPreferencesAsync.empty();
      SharedPreferencesAsyncPlatform.instance = platform;
    });

    test('the user-defaults store uses the theme.appearance key', () async {
      expect(SharedPreferencesAppearanceStore.key, 'theme.appearance');
      final store = SharedPreferencesAppearanceStore();
      expect(await store.read(), isNull);
      await store.write('dark');
      expect(await platform.getString('theme.appearance', options), 'dark');
      expect(await store.read(), 'dark');
    });

    test('a new installation starts with System', () async {
      final appearance = await AppearanceController.load(
        SharedPreferencesAppearanceStore(),
      );
      expect(appearance.mode, AppearanceMode.system);
      expect(appearance.themeMode, ThemeMode.system);
    });

    test('a stored choice is restored at startup', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'theme.appearance': 'light',
          });
      final appearance = await loadAppearance();
      expect(appearance.mode, AppearanceMode.light);
    });

    test('an unknown stored value falls back to System', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'theme.appearance': 'sepia',
          });
      expect((await loadAppearance()).mode, AppearanceMode.system);
    });

    test('a stored value of another type falls back to System', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({'theme.appearance': 2});
      expect((await loadAppearance()).mode, AppearanceMode.system);
    });

    test('an unreadable store falls back to System', () async {
      final appearance = await AppearanceController.load(_FailingStore());
      expect(appearance.mode, AppearanceMode.system);
    });

    test('changes notify at once and are written', () async {
      final store = SharedPreferencesAppearanceStore();
      final appearance = await AppearanceController.load(store);
      var notified = 0;
      appearance.addListener(() => notified++);
      await appearance.setMode(AppearanceMode.dark);
      expect(appearance.themeMode, ThemeMode.dark);
      expect(notified, 1);
      expect(await platform.getString('theme.appearance', options), 'dark');
      await appearance.setMode(AppearanceMode.dark);
      expect(notified, 1);
      await appearance.setMode(AppearanceMode.system);
      expect(await platform.getString('theme.appearance', options), 'system');
      final reloaded = await AppearanceController.load(store);
      expect(reloaded.mode, AppearanceMode.system);
    });

    test('a failed write keeps the choice for the session', () async {
      final appearance = AppearanceController(store: _FailingStore());
      await expectLater(
        appearance.setMode(AppearanceMode.light),
        throwsStateError,
      );
      expect(appearance.mode, AppearanceMode.light);
    });
  });

  group('themes', () {
    test('both themes carry a complete palette', () {
      for (final brightness in Brightness.values) {
        final theme = atlasTheme(brightness);
        expect(theme.brightness, brightness);
        final palette = theme.extension<AtlasPalette>();
        expect(palette, isNotNull, reason: '$brightness');
        expect(
          palette,
          brightness == Brightness.dark
              ? AtlasPalette.dark
              : AtlasPalette.light,
        );
        expect(palette!.colors.length, 34);
        for (final entry in palette.colors.entries) {
          expect(entry.value.a, greaterThan(0), reason: entry.key);
        }
      }
      expect(AtlasPalette.light.colors.keys, AtlasPalette.dark.colors.keys);
    });

    test('the dark theme reproduces the original appearance', () {
      final theme = atlasTheme(Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xff10151f));
      expect(theme.colorScheme.surface, const Color(0xff171e2b));
      expect(theme.dividerColor, const Color(0xff293244));
      expect(theme.textTheme.bodyMedium?.color, const Color(0xffe4eaf5));
      expect(theme.textTheme.bodySmall?.color, const Color(0xff98a6bc));
      expect(theme.inputDecorationTheme.fillColor, const Color(0xff111824));
      expect(theme.dialogTheme.backgroundColor, const Color(0xff171e2b));
      final filled = theme.filledButtonTheme.style!;
      expect(filled.backgroundColor!.resolve({}), const Color(0xffb2c7ff));
      expect(filled.foregroundColor!.resolve({}), const Color(0xff12203b));
      expect(
        theme.outlinedButtonTheme.style!.foregroundColor!.resolve({}),
        const Color(0xffd6e0f2),
      );
      final dark = AtlasPalette.dark;
      expect(dark.accent, const Color(0xff8fafff));
      expect(dark.success, const Color(0xff77d8b4));
      expect(dark.reserved, const Color(0xffdbc18b));
      expect(dark.danger, const Color(0xffff8c8c));
      expect(dark.warning, const Color(0xffe6c583));
      expect(dark.sidebar, const Color(0xff131a26));
      expect(dark.detailsPanel, const Color(0xff141c28));
      expect(dark.barrier, const Color(0x9910151f));
      expect(dark.mapFree, const Color(0xff77d8b4));
      expect(dark.mapBlocked, const Color(0xffdbc18b));
    });

    test('the palette lerps and copies every colour', () {
      final halfway = AtlasPalette.dark.lerp(AtlasPalette.light, 0.5);
      expect(halfway.colors.length, 34);
      expect(
        AtlasPalette.dark.lerp(AtlasPalette.light, 1).colors,
        AtlasPalette.light.colors,
      );
      expect(AtlasPalette.dark.lerp(null, 0.5), AtlasPalette.dark);
      final copy = AtlasPalette.light.copyWith(accent: const Color(0xff000000));
      expect(copy.accent, const Color(0xff000000));
      expect(copy.surface, AtlasPalette.light.surface);
    });
  });

  group('contrast (WCAG AA, 4.5:1)', () {
    const surfaces = [
      'background',
      'surface',
      'sidebar',
      'sidebarCard',
      'detailsPanel',
      'tableHeader',
      'inputFill',
    ];
    for (final (name, palette) in [
      ('dark', AtlasPalette.dark),
      ('light', AtlasPalette.light),
    ]) {
      test('$name primary and secondary text on the main surfaces', () {
        final colors = palette.colors;
        for (final surface in surfaces) {
          for (final text in ['text', 'textSecondary']) {
            final ratio = contrast(colors[text]!, colors[surface]!);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$name $text on $surface: ${ratio.toStringAsFixed(2)}',
            );
          }
        }
      });

      test('$name state, accent and selection text', () {
        final colors = palette.colors;
        for (final text in [
          'accent',
          'success',
          'reserved',
          'warning',
          'danger',
          'plannerError',
          'outlinedForeground',
        ]) {
          for (final surface in ['background', 'surface', 'detailsPanel']) {
            final ratio = contrast(colors[text]!, colors[surface]!);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$name $text on $surface: ${ratio.toStringAsFixed(2)}',
            );
          }
        }
        for (final (text, background) in [
          ('textSelected', 'navSelected'),
          ('onAccentStrong', 'accentStrong'),
          ('conflictBadgeText', 'conflictBadgeBackground'),
          ('text', 'rowSelected'),
          ('accent', 'candidateSelected'),
          ('textSecondary', 'candidateSelected'),
        ]) {
          final ratio = contrast(colors[text]!, colors[background]!);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$name $text on $background: ${ratio.toStringAsFixed(2)}',
          );
        }
      });
    }

    test('light status badges stay readable on their tint', () {
      final p = AtlasPalette.light;
      for (final base in [p.surface, p.rowSelected]) {
        for (final color in [
          p.success,
          p.reserved,
          p.accent,
          p.textSecondary,
        ]) {
          final badge = Color.alphaBlend(color.withValues(alpha: .1), base);
          expect(contrast(color, badge), greaterThanOrEqualTo(4.5));
        }
      }
    });

    test('light planner map fills and frame reach 3:1 non-text contrast', () {
      final p = AtlasPalette.light;
      for (final (color, opacity) in [
        (p.mapFree, p.mapFreeOpacity),
        (p.mapBlocked, p.mapBlockedOpacity),
        (p.mapOutline, 1.0),
      ]) {
        final fill = Color.alphaBlend(
          color.withValues(alpha: opacity),
          p.surface,
        );
        expect(contrast(fill, p.surface), greaterThanOrEqualTo(3.0));
      }
    });

    test('light faint text meets AA on the sidebar', () {
      final p = AtlasPalette.light;
      expect(contrast(p.textFaint, p.sidebar), greaterThanOrEqualTo(4.5));
    });
  });
}
