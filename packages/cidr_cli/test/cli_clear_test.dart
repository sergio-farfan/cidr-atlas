// CIDR Atlas
// Command-line clear tests: confirmation, scope, history, validation and
// refusal to create a missing inventory.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';
import 'dart:io';

import 'package:cidr_cli/cidr_cli.dart';
import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _pool = PrefixRecord(
  id: 'example-pool',
  cidr: '10.64.0.0/16',
  name: 'Fictional pool',
  routingDomain: 'example-corporate',
  kind: PrefixKind.allocation,
);
const _vcn = PrefixRecord(
  id: 'example-vcn',
  cidr: '10.64.0.0/20',
  name: 'Fictional VCN',
  routingDomain: 'example-corporate',
  parentId: 'example-pool',
  status: PrefixStatus.active,
);
const _subnet = PrefixRecord(
  id: 'example-subnet',
  cidr: '10.64.1.0/24',
  name: 'Fictional subnet',
  routingDomain: 'example-corporate',
  kind: PrefixKind.subnet,
  parentId: 'example-vcn',
  status: PrefixStatus.active,
);
const _lab = PrefixRecord(
  id: 'example-lab',
  cidr: '172.20.0.0/16',
  name: 'Fictional lab',
  routingDomain: 'example-lab',
  status: PrefixStatus.active,
);

void main() {
  late Directory temporary;
  late String database;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('cidr_cli_clear_');
    database = '${temporary.path}/inventory.sqlite';
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  ({int code, String output, String error}) run(List<String> args,
      {String? db}) {
    final output = StringBuffer();
    final error = StringBuffer();
    final code = runCidrctl(['--db', db ?? database, ...args],
        out: output, err: error, environment: const {});
    return (code: code, output: '$output', error: '$error');
  }

  void seed(List<PrefixRecord> records) {
    final store = InventoryStore.open(database);
    try {
      if (records.isNotEmpty) store.saveAll(records);
    } finally {
      store.close();
    }
  }

  ({List<PrefixRecord> records, List<AuditEntry> history}) snapshot() {
    final store = InventoryStore.open(database);
    try {
      return (records: store.list(), history: store.history());
    } finally {
      store.close();
    }
  }

  List<String> ids(List<PrefixRecord> records) =>
      [for (final record in records) record.id];

  test('without --yes is a usage error that suggests export first', () {
    seed([_pool, _vcn, _subnet]);
    final before = snapshot();
    final result = run(['clear']);
    expect(result.code, 2);
    expect(result.output, isEmpty);
    expect(
        result.error,
        contains('Usage error: clear deletes local inventory '
            'records and requires --yes.'));
    expect(result.error, contains('OCI resources are not changed.'));
    expect(result.error, contains('cidrctl export --file BACKUP.json'));
    final after = snapshot();
    expect(ids(after.records), ids(before.records));
    expect(after.history.length, before.history.length);
  });

  test('without --yes on a missing inventory still creates nothing', () {
    final result = run(['clear']);
    expect(result.code, 2);
    expect(temporary.listSync(), isEmpty);
  });

  test('clears every local record with one history entry', () {
    seed([_pool, _vcn, _subnet, _lab]);
    final before = snapshot();
    final result = run(['clear', '--yes']);
    expect(result.code, 0, reason: result.error);
    expect(
        result.output,
        'Cleared 4 records from the local inventory. '
        'OCI resources were not changed.\n');
    expect(result.error, isEmpty);
    final after = snapshot();
    expect(after.records, isEmpty);
    expect(after.history.length, before.history.length + 1);
    expect(after.history.first.action, 'delete');
  });

  test('clears only the selected routing domain', () {
    seed([_pool, _vcn, _subnet, _lab]);
    final before = snapshot();
    final result =
        run(['clear', '--routing-domain', 'example-corporate', '--yes']);
    expect(result.code, 0, reason: result.error);
    expect(
        result.output,
        'Cleared 3 records from routing domain example-corporate. '
        'OCI resources were not changed.\n');
    final after = snapshot();
    expect(ids(after.records), ['example-lab']);
    expect(after.history.length, before.history.length + 1);
  });

  test('uses the singular for one record and works through the async entry',
      () async {
    seed([_pool, _lab]);
    final output = StringBuffer();
    final error = StringBuffer();
    final code = await runCidrctlAsync(
        ['--db', database, 'clear', '--routing-domain', 'example-lab', '--yes'],
        out: output,
        err: error,
        environment: const {});
    expect(code, 0, reason: '$error');
    expect('$output', startsWith('Cleared 1 record from routing domain '));
    expect(ids(snapshot().records), ['example-pool']);
  });

  test('accepts the command --db option', () {
    seed([_lab]);
    final output = StringBuffer();
    final code = runCidrctl(['clear', '--db', database, '--yes'],
        out: output, err: StringBuffer(), environment: const {});
    expect(code, 0);
    expect(snapshot().records, isEmpty);
  });

  test('an empty inventory has nothing to clear and writes nothing', () {
    seed([]);
    final before = snapshot();
    final result = run(['clear', '--yes']);
    expect(result.code, 0);
    expect(result.output, 'No records to clear.\n');
    expect(result.error, isEmpty);
    expect(snapshot().history.length, before.history.length);
  });

  test('an unknown routing domain warns and writes nothing', () {
    seed([_pool, _vcn, _subnet, _lab]);
    final before = snapshot();
    final result =
        run(['clear', '--routing-domain', 'Example-Corporate', '--yes']);
    expect(result.code, 0);
    expect(result.output, 'No records to clear.\n');
    expect(
        result.error,
        contains('Warning: routing domain "Example-Corporate" has no '
            'existing non-retired records'));
    expect(result.error, contains('Did you mean: example-corporate?'));
    final after = snapshot();
    expect(ids(after.records), ids(before.records));
    expect(after.history.length, before.history.length);
  });

  test('clears a routing domain whose records are all retired', () {
    seed([_lab.copyWith(status: PrefixStatus.retired), _pool]);
    final result = run(['clear', '--routing-domain', 'example-lab', '--yes']);
    expect(result.code, 0);
    expect(result.error, isEmpty);
    expect(ids(snapshot().records), ['example-pool']);
  });

  test('a cross-domain parent reference fails with no partial write', () {
    seed([_pool, _vcn, _subnet, _lab]);
    // Simulates a legacy inventory written before cross-domain parents were
    // refused: a lab record names the corporate pool as its parent.
    final raw = sqlite3.open(database);
    try {
      final orphan = _lab.copyWith(parentId: 'example-pool');
      raw.execute('UPDATE prefixes SET document = ? WHERE id = ?',
          [jsonEncode(orphan.toJson()), orphan.id]);
    } finally {
      raw.dispose();
    }
    final before = snapshot();
    final result =
        run(['clear', '--routing-domain', 'example-corporate', '--yes']);
    expect(result.code, 1);
    expect(result.output, isEmpty);
    expect(result.error, startsWith('Clear was not saved: '));
    expect(result.error, contains('Fictional lab'));
    final after = snapshot();
    expect(ids(after.records), ids(before.records));
    expect(after.history.length, before.history.length);
  });

  test('a missing inventory fails and creates nothing', () {
    final result = run(['clear', '--yes']);
    expect(result.code, 1);
    expect(result.output, isEmpty);
    expect(result.error, startsWith('Inventory not found: $database.'));
    expect(temporary.listSync(), isEmpty);

    final nested = '${temporary.path}/missing/inventory.sqlite';
    final nestedResult = run(['clear', '--yes'], db: nested);
    expect(nestedResult.code, 1);
    expect(nestedResult.error, contains('Inventory not found'));
    expect(temporary.listSync(), isEmpty);
  });

  test('a directory path is a file error', () {
    final result = run(['clear', '--yes'], db: temporary.path);
    expect(result.code, 1);
    expect(
        result.error,
        contains('File error: The database path is a '
            'directory'));
  });

  test('rejects positional arguments and a blank routing domain', () {
    seed([_lab]);
    expect(run(['clear', 'everything', '--yes']).code, 2);
    final blank = run(['clear', '--routing-domain', ' ', '--yes']);
    expect(blank.code, 2);
    expect(blank.error, contains('--routing-domain cannot be blank.'));
    expect(ids(snapshot().records), ['example-lab']);
  });

  test('help documents clear with examples', () {
    final root = run(['--help']);
    expect(root.output, contains('history, clear'));
    expect(root.output, contains('Clear deletes local records only'));
    final help = run(['clear', '--help']);
    expect(help.code, 0);
    expect(help.output, contains('Usage: cidrctl clear [options]'));
    expect(help.output, contains('--yes'));
    expect(help.output,
        contains('cidrctl clear --routing-domain fictional-connected --yes'));
    expect(help.output, contains('cidrctl export --file'));
  });
}
