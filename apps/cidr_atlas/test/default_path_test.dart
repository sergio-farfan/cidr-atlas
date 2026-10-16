// CIDR Atlas
// Application inventory path agreement with the shared CLI default.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_atlas/main.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const environment = {
    'HOME': '/Users/fictional',
    'APPDATA': r'C:\Users\fictional\AppData\Roaming',
    'XDG_DATA_HOME': '/home/fictional/.data',
  };

  test('macOS path is byte-identical to the v0.3.0 application layout', () {
    // v0.3.0 used the parent of path_provider's bundle-specific Application
    // Support directory, then cidr_atlas/inventory.sqlite.
    expect(
      atlasDatabasePath(environment, operatingSystem: 'macos'),
      '/Users/fictional/Library/Application Support/cidr_atlas/inventory.sqlite',
    );
  });

  test('every desktop platform uses the cidrctl default path', () {
    for (final system in ['macos', 'windows', 'linux']) {
      expect(
        atlasDatabasePath(environment, operatingSystem: system),
        defaultDatabasePath(environment, operatingSystem: system),
      );
    }
    expect(
      atlasDatabasePath(environment, operatingSystem: 'linux'),
      '/home/fictional/.data/cidr_atlas/inventory.sqlite',
    );
    expect(
      atlasDatabasePath(environment, operatingSystem: 'windows'),
      r'C:\Users\fictional\AppData\Roaming/cidr_atlas/inventory.sqlite',
    );
  });

  test('a missing home directory is reported instead of guessed', () {
    expect(
      () => atlasDatabasePath(const {}, operatingSystem: 'macos'),
      throwsStateError,
    );
  });
}
