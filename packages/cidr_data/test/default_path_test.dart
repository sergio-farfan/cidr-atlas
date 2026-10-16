// CIDR Atlas
// Default inventory database location tests for every desktop layout.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

void main() {
  group('macOS', () {
    test('matches the v0.3.0 application support path byte for byte', () {
      expect(
        defaultDatabasePath(
          {'HOME': '/Users/example', 'XDG_DATA_HOME': '/ignored'},
          operatingSystem: 'macos',
        ),
        '/Users/example/Library/Application Support/cidr_atlas/inventory.sqlite',
      );
    });

    test('falls back to USERPROFILE and fails without a home', () {
      expect(
        defaultDatabasePath({'USERPROFILE': '/Users/other'},
            operatingSystem: 'macos'),
        '/Users/other/Library/Application Support/cidr_atlas/inventory.sqlite',
      );
      expect(
        () => defaultDatabasePath({}, operatingSystem: 'macos'),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            'HOME is not set; specify --db.')),
      );
    });
  });

  group('Linux', () {
    test('uses an absolute XDG_DATA_HOME', () {
      expect(
        defaultDatabasePath(
          {'HOME': '/home/example', 'XDG_DATA_HOME': '/data/example'},
          operatingSystem: 'linux',
        ),
        '/data/example/cidr_atlas/inventory.sqlite',
      );
    });

    test('ignores an empty or relative XDG_DATA_HOME', () {
      for (final dataHome in ['', 'relative/share', './share', '~/share']) {
        expect(
          defaultDatabasePath(
            {'HOME': '/home/example', 'XDG_DATA_HOME': dataHome},
            operatingSystem: 'linux',
          ),
          '/home/example/.local/share/cidr_atlas/inventory.sqlite',
          reason: dataHome,
        );
      }
    });

    test('falls back to HOME and fails without one', () {
      expect(
        defaultDatabasePath({'HOME': '/home/example'},
            operatingSystem: 'linux'),
        '/home/example/.local/share/cidr_atlas/inventory.sqlite',
      );
      expect(
        () => defaultDatabasePath({'XDG_DATA_HOME': 'relative'},
            operatingSystem: 'linux'),
        throwsStateError,
      );
    });
  });

  group('Windows', () {
    test('uses APPDATA when present', () {
      expect(
        defaultDatabasePath(
          {
            'APPDATA': r'C:\Users\example\AppData\Roaming',
            'USERPROFILE': r'C:\Users\example',
          },
          operatingSystem: 'windows',
        ),
        r'C:\Users\example\AppData\Roaming/cidr_atlas/inventory.sqlite',
      );
    });

    test('fails when APPDATA is missing', () {
      expect(
        () => defaultDatabasePath({'USERPROFILE': r'C:\Users\example'},
            operatingSystem: 'windows'),
        throwsA(isA<StateError>().having((error) => error.message, 'message',
            'APPDATA is not set; specify --db.')),
      );
    });
  });
}
