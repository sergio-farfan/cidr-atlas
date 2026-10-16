// CIDR Atlas
// Application startup and local database setup.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'controller.dart';
import 'oci_dialog.dart';

/// The inventory database the application opens: the same default path as
/// `cidrctl`, computed by the shared `cidr_data` function.
String atlasDatabasePath(
  Map<String, String> environment, {
  String? operatingSystem,
}) => defaultDatabasePath(environment, operatingSystem: operatingSystem);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final databasePath = atlasDatabasePath(Platform.environment);
    await File(databasePath).parent.create(recursive: true);
    final store = InventoryStore.open(databasePath);
    runApp(
      AtlasApp(
        controller: AtlasController(store, databasePath: databasePath),
        ociClientFactory: OciDiscoveryDialog.defaultClientFactory,
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
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
