// CIDR Atlas
// Appearance preference: System, Light or Dark, kept in user defaults.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The appearance choices offered in Settings.
enum AppearanceMode {
  system('System', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  const AppearanceMode(this.label, this.themeMode);

  /// The label shown in Settings.
  final String label;

  /// The Flutter theme mode; [ThemeMode.system] follows macOS.
  final ThemeMode themeMode;

  /// The stored value: `system`, `light` or `dark`.
  String get storageValue => name;

  /// Parses a stored value. A missing or unknown value is [system].
  static AppearanceMode parse(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return system;
  }
}

/// Where the appearance preference is kept.
abstract interface class AppearanceStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Keeps the preference in the platform preference store (user defaults on
/// macOS, domain `dev.cidratlas.desktop`) under [key].
class SharedPreferencesAppearanceStore implements AppearanceStore {
  SharedPreferencesAppearanceStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// The preference key; the values are the [AppearanceMode] names.
  static const key = 'theme.appearance';

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read() => _preferences.getString(key);

  @override
  Future<void> write(String value) => _preferences.setString(key, value);
}

/// Keeps the preference in memory only; used when no store is injected and
/// by tests, so they never touch real user defaults.
class MemoryAppearanceStore implements AppearanceStore {
  MemoryAppearanceStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// The current appearance; changes apply at once and are persisted.
class AppearanceController extends ChangeNotifier {
  AppearanceController({
    AppearanceStore? store,
    this._mode = AppearanceMode.system,
  }) : store = store ?? MemoryAppearanceStore();

  /// Reads the stored preference. A read failure or an unknown value starts
  /// with [AppearanceMode.system] and never blocks startup.
  static Future<AppearanceController> load(AppearanceStore store) async {
    var mode = AppearanceMode.system;
    try {
      mode = AppearanceMode.parse(await store.read());
    } catch (error) {
      debugPrint('CIDR Atlas could not read the appearance preference: $error');
    }
    return AppearanceController(store: store, mode: mode);
  }

  final AppearanceStore store;
  AppearanceMode _mode;

  AppearanceMode get mode => _mode;
  ThemeMode get themeMode => _mode.themeMode;

  /// Applies [mode] immediately, then persists it. A write failure keeps the
  /// choice for this session and is reported to the caller.
  Future<void> setMode(AppearanceMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await store.write(mode.storageValue);
  }
}
