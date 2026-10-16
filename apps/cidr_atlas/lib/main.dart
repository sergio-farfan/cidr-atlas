// CIDR Atlas
// Application startup and local database setup.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'appearance.dart';
import 'controller.dart';
import 'oci_dialog.dart';
import 'theme.dart';

/// The inventory database the application opens: the same default path as
/// `cidrctl`, computed by the shared `cidr_data` function.
String atlasDatabasePath(
  Map<String, String> environment, {
  String? operatingSystem,
}) => defaultDatabasePath(environment, operatingSystem: operatingSystem);

/// Loads the appearance preference from user defaults. A missing, unknown or
/// unreadable preference starts with System and never blocks the inventory
/// from opening; if the preference store is unavailable, changes last for
/// the session only.
Future<AppearanceController> loadAppearance() async {
  try {
    // A preference read must never hold the window back.
    return await AppearanceController.load(SharedPreferencesAppearanceStore())
        .timeout(const Duration(seconds: 2));
  } catch (error) {
    debugPrint('CIDR Atlas could not open its preferences: $error');
    return AppearanceController();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appearance = await loadAppearance();
  try {
    final databasePath = atlasDatabasePath(Platform.environment);
    await File(databasePath).parent.create(recursive: true);
    final store = InventoryStore.open(databasePath);
    runApp(
      AtlasApp(
        controller: AtlasController(store, databasePath: databasePath),
        appearance: appearance,
        ociClientFactory: OciDiscoveryDialog.defaultClientFactory,
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        theme: atlasTheme(Brightness.light),
        darkTheme: atlasTheme(Brightness.dark),
        themeMode: appearance.themeMode,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.storage_rounded, size: 40),
                    const SizedBox(height: 20),
                    const Text(
                      'CIDR Atlas could not open its inventory',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText('$error'),
                    const SizedBox(height: 16),
                    const Text(
                      'Check that your Application Support folder is writable, then reopen the app. Existing inventory files have not been reset.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
