// CIDR Atlas
// Application startup and local database setup.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:io';

import 'package:cidr_data/cidr_data.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final base = await getApplicationSupportDirectory();
    // Match cidrctl's default path. path_provider returns the bundle-specific
    // directory on macOS, so use its Application Support parent there.
    final root = Platform.isMacOS ? base.parent.path : base.path;
    final directory = Directory(p.join(root, 'cidr_atlas'));
    await directory.create(recursive: true);
    final databasePath = p.join(directory.path, 'inventory.sqlite');
    final store = InventoryStore.open(databasePath);
    runApp(AtlasApp(
        controller: AtlasController(store, databasePath: databasePath)));
  } catch (error) {
    runApp(MaterialApp(
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
                                    fontSize: 24, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            SelectableText('$error'),
                            const SizedBox(height: 16),
                            const Text(
                                'Check that your Application Support folder is writable, then reopen the app. Existing inventory files have not been reset.')
                          ],
                        )))))));
  }
}
