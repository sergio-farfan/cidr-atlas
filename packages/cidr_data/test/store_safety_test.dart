// CIDR Atlas
// Store safety tests: SQL-level rollback, busy connections, delete refusals,
// partial-column merges and OCI reconciliation notices.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'import_test.dart' show ociBundle, vcn;

PrefixRecord record(
  String id,
  String cidr, {
  String parentId = '',
  PrefixKind kind = PrefixKind.vcn,
  String routingDomain = 'corp',
}) =>
    PrefixRecord(
      id: id,
      cidr: cidr,
      name: id,
      routingDomain: routingDomain,
      parentId: parentId,
      kind: kind,
    );

String _temporaryDatabase(String label) {
  final directory = Directory.systemTemp.createTempSync('cidr-atlas-$label-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return '${directory.path}/inventory.sqlite';
}

Map<String, dynamic> _bundleAt(String collectedAt, {String? name}) {
  final bundle = ociBundle(
    vcns: [
      {...vcn, if (name != null) 'display-name': name},
    ],
    subnets: [],
  );
  return {
    ...bundle,
    'metadata': {
      ...bundle['metadata'] as Map<String, dynamic>,
      'collectedAt': collectedAt,
    },
  };
}

void main() {
  group('SQL-level write failures roll back records and history', () {
    final operations = <String, void Function(InventoryStore)>{
      'saveAll': (store) => store.saveAll([
            record('new-a', '10.8.0.0/16'),
            record('new-b', '10.9.0.0/16'),
          ]),
      'applyImport': (store) => store.applyImport(InventoryImport.csv(
            'id,cidr,name,routingDomain\nimported,10.7.0.0/16,Imported,corp\n',
          )),
      'reserve': (store) => store.reserve(record('reserved', '10.6.0.0/16')),
    };
    for (final table in ['prefixes', 'audit_entries']) {
      for (final raise in ['ABORT', 'ROLLBACK']) {
        for (final operation in operations.entries) {
          test('${operation.key} with RAISE($raise) on $table', () {
            final path = _temporaryDatabase('trigger');
            final store = InventoryStore.open(path);
            addTearDown(store.close);
            store.save(record('base', '172.16.0.0/16'));
            final raw = sqlite3.open(path);
            addTearDown(raw.dispose);
            raw.execute('CREATE TRIGGER refuse BEFORE INSERT ON $table '
                "BEGIN SELECT RAISE($raise, 'fictional trigger refusal'); END");

            expect(
              () => operation.value(store),
              throwsA(isA<SqliteException>().having(
                (error) => error.toString(),
                'message',
                contains('fictional trigger refusal'),
              )),
            );
            expect(store.list().map((item) => item.id), ['base']);
            expect(store.history(), hasLength(1));

            raw.execute('DROP TRIGGER refuse');
            operation.value(store);
            expect(store.list().length, greaterThan(1));
            expect(store.history(), hasLength(2));
          });
        }
      }
    }
  });

  test(
      'applyImport fails busy without partial state while another connection '
      'holds the write lock', () {
    final path = _temporaryDatabase('busy');
    final store = InventoryStore.open(path);
    addTearDown(store.close);
    store.save(record('base', '172.16.0.0/16'));
    final preview = InventoryImport.csv(
      'id,cidr,name,routingDomain\nimported,10.7.0.0/16,Imported,corp\n',
    );
    final other = sqlite3.open(path);
    addTearDown(other.dispose);
    other.execute('BEGIN IMMEDIATE');
    expect(
      () => store.applyImport(preview),
      throwsA(isA<SqliteException>()
          .having((error) => error.resultCode, 'resultCode', 5)),
    );
    other.execute('ROLLBACK');
    expect(store.list().map((item) => item.id), ['base']);
    expect(store.history(), hasLength(1));
    store.applyImport(preview);
    expect(store.list(), hasLength(2));
  }, timeout: const Timeout(Duration(seconds: 30)));

  group('delete', () {
    late InventoryStore store;
    setUp(() => store = InventoryStore.memory());
    tearDown(() => store.close());

    void seed() => store.saveAll([
          record('pool', '10.0.0.0/8', kind: PrefixKind.allocation),
          record('vcn-a', '10.1.0.0/16', parentId: 'pool'),
          record('vcn-b', '10.2.0.0/16', parentId: 'pool'),
          record('subnet', '10.1.1.0/24',
              parentId: 'vcn-a', kind: PrefixKind.subnet),
        ]);

    test('refuses a parent and explains which children block it', () {
      seed();
      expect(
        () => store.delete('pool'),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Cannot delete pool (10.0.0.0/8): 2 child prefixes reference it: '
              'vcn-a (10.1.0.0/16), vcn-b (10.2.0.0/16). '
              'Delete or re-parent them first.',
        )),
      );
      expect(
        () => store.delete('vcn-a'),
        throwsA(isA<FormatException>().having(
          (error) => error.message,
          'message',
          startsWith('Cannot delete vcn-a (10.1.0.0/16): 1 child prefix '
              'references it: subnet (10.1.1.0/24).'),
        )),
      );
      expect(store.list(), hasLength(4));
      expect(store.history(), hasLength(1));
    });

    test('deleteAll removes a hierarchy in any order with one audit entry', () {
      seed();
      store.save(record('other', '192.168.0.0/16'));
      store.deleteAll(['pool', 'subnet', 'missing', 'vcn-a', 'vcn-b', 'pool']);
      expect(store.list().map((item) => item.id), ['other']);
      expect(store.history(), hasLength(3));
      expect(store.history().first.action, 'delete');
      expect(store.history().first.summary, startsWith('Deleted 4 prefixes'));
    });

    test('deleteAll refuses a partial hierarchy atomically', () {
      seed();
      expect(
        () => store.deleteAll(['subnet', 'pool']),
        throwsA(isA<FormatException>().having((error) => error.message,
            'message', startsWith('Cannot delete pool (10.0.0.0/8)'))),
      );
      expect(store.list(), hasLength(4));
      expect(store.history(), hasLength(1));
      store.deleteAll([]);
      store.deleteAll(['missing']);
      expect(store.history(), hasLength(1));
    });
  });

  group('imports onto existing records', () {
    late InventoryStore store;
    setUp(() => store = InventoryStore.memory());
    tearDown(() => store.close());

    test('an id-matched partial-column CSV changes only its columns', () {
      final verifiedAt = DateTime.utc(2026, 1, 1);
      store.save(PrefixRecord(
        id: 'x',
        cidr: '10.0.0.0/16',
        name: 'Main',
        routingDomain: 'd',
        status: PrefixStatus.active,
        customer: 'Fictional client',
        owner: 'Architect',
        notes: 'Keep',
        environment: 'prod',
        resourceId: 'ocid1.vcn.oc1.example',
        source: 'oci',
        verifiedAt: verifiedAt,
      ));
      final preview = InventoryImport.csv(
        'id,cidr,name,routingDomain,environment\n'
        'x,10.0.0.0/16,Main renamed,d,\n'
        'y,10.1.0.0/16,New record,d,\n',
        existingRecords: store.list(),
      );
      expect(preview.canApply, isTrue, reason: preview.errors.join());
      store.applyImport(preview);

      final updated = store.list().singleWhere((item) => item.id == 'x');
      expect(updated.name, 'Main renamed');
      expect(updated.environment, '', reason: 'a supplied blank cell clears');
      expect(updated.status, PrefixStatus.active);
      expect(updated.customer, 'Fictional client');
      expect(updated.owner, 'Architect');
      expect(updated.notes, 'Keep');
      expect(updated.resourceId, 'ocid1.vcn.oc1.example');
      expect(updated.source, 'oci');
      expect(updated.verifiedAt, verifiedAt);

      final created = store.list().singleWhere((item) => item.id == 'y');
      expect(created.status, PrefixStatus.reserved);
      expect(created.source, 'csv');
    });

    test('a retired record still observed live is preserved and reported', () {
      store.applyImport(InventoryImport.json(
          jsonEncode(_bundleAt('2026-10-15T18:30:00Z')),
          routingDomain: 'corp'));
      final target =
          store.list().firstWhere((item) => item.cidr == '10.40.0.0/16');
      store.save(target.copyWith(status: PrefixStatus.retired));
      // A manually entered record linked to the same OCI resource is matched
      // by natural identity rather than by id.
      final observed41 =
          store.list().singleWhere((item) => item.cidr == '10.41.0.0/16');
      store.delete(observed41.id);
      store.save(observed41.copyWith(
          id: 'manual-41', status: PrefixStatus.retired, source: 'manual'));

      final refresh = InventoryImport.json(
        jsonEncode(_bundleAt('2026-10-16T08:00:00Z')),
        routingDomain: 'corp',
        existingRecords: store.list(),
      );
      final notice = refresh.warnings
          .singleWhere((warning) => warning.contains('marked retired'));
      expect(
          notice,
          startsWith('2 records are marked retired but still '
              'observed live by OCI'));
      expect(notice, contains('(10.40.0.0/16)'));
      expect(notice, contains('treated as free'));
      store.applyImport(refresh);
      expect(store.history().first.summary, contains(notice));
      for (final cidr in ['10.40.0.0/16', '10.41.0.0/16']) {
        expect(
          store.list().singleWhere((item) => item.cidr == cidr).status,
          PrefixStatus.retired,
        );
      }

      final again = InventoryImport.json(
        jsonEncode(_bundleAt('2026-10-17T08:00:00Z')),
        routingDomain: 'corp',
        existingRecords: [
          for (final item in store.list())
            item.copyWith(status: PrefixStatus.active),
        ],
      );
      expect(again.warnings.join(), isNot(contains('marked retired')));
    });

    test('an older bundle is reported but still merged as before', () {
      store.applyImport(InventoryImport.json(
          jsonEncode(_bundleAt('2026-10-16T00:00:00Z', name: 'New name')),
          routingDomain: 'corp'));
      final stale = InventoryImport.json(
        jsonEncode(_bundleAt('2026-01-01T00:00:00Z', name: 'Stale name')),
        routingDomain: 'corp',
        existingRecords: store.list(),
      );
      final notice = stale.warnings
          .singleWhere((warning) => warning.contains('newer observation'));
      expect(notice, startsWith('3 records have a newer observation'));
      expect(notice, contains('observed at 2026-10-16T00:00:00.000Z'));
      expect(notice, contains('back to 2026-01-01T00:00:00.000Z'));
      store.applyImport(stale);
      expect(store.history().first.summary, contains(notice));
      for (final item in store.list()) {
        expect(item.name, 'Stale name');
        expect(item.verifiedAt, DateTime.utc(2026, 1, 1));
      }

      final newer = InventoryImport.json(
        jsonEncode(_bundleAt('2026-10-17T00:00:00Z')),
        routingDomain: 'corp',
        existingRecords: store.list(),
      );
      expect(newer.warnings.join(), isNot(contains('newer observation')));
    });
  });

  test('conflict rejection checks only the changed records', () {
    final store = InventoryStore.memory();
    addTearDown(store.close);
    store.saveAll([
      record('x', '10.0.0.0/16'),
      record('y', '10.0.0.0/24'),
      record('other-domain', '172.20.0.0/16', routingDomain: 'isolated'),
    ]);
    store.save(record('safe', '172.20.0.0/16'), rejectConflicts: true);
    expect(
      () => store.save(record('unsafe', '10.0.8.0/24'), rejectConflicts: true),
      throwsA(isA<InventoryConflictException>().having(
        (error) => error.conflicts
            .map((conflict) => {conflict.first.id, conflict.second.id}),
        'conflicts',
        [
          {'x', 'unsafe'},
        ],
      )),
    );
  });
}
