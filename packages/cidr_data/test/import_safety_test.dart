// CIDR Atlas
// Import previews: partial columns, id-less rows, formula escaping,
// observation times, OCI alias spellings, truncation and reconciliation notes.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:csv/csv.dart';
import 'package:test/test.dart';

import 'import_test.dart' show ociBundle, vcn;

void main() {
  group('partial-column CSV', () {
    test('records the header columns it supplied', () {
      final preview = InventoryImport.csv(
          'id,CIDR,name,routing_domain\nx,10.0.0.0/16,Main,d\n');
      expect(preview.presentColumns, {'id', 'cidr', 'name', 'routingDomain'});
      expect(InventoryImport.exportCsv([]), startsWith('id,cidr'));
      expect(
        InventoryImport.json(
          InventoryImport.exportJson([]),
          routingDomain: '',
        ).presentColumns,
        isNull,
      );
    });

    test('preview validates an update as merged onto the existing record', () {
      const parent = PrefixRecord(
        id: 'p',
        cidr: '10.0.0.0/16',
        name: 'Pool',
        routingDomain: 'd',
        kind: PrefixKind.allocation,
      );
      const child = PrefixRecord(
        id: 'c',
        cidr: '10.0.1.0/24',
        name: 'Child',
        routingDomain: 'd',
        parentId: 'p',
      );
      // The CSV keeps the child's parent link but moves it outside the pool.
      final preview = InventoryImport.csv(
        'id,cidr,name,routingDomain\nc,192.168.0.0/24,Child,d\n',
        existingRecords: [parent, child],
      );
      expect(preview.canApply, isFalse);
      expect(preview.errors.join(), contains('c'));
    });
  });

  group('CSV rows without ids', () {
    test('a generated-id collision names both rows', () {
      final preview = InventoryImport.csv(
        'cidr,name,routingDomain\n'
        '10.0.0.0/16,Customer A,shared\n'
        '10.0.0.0/16,Customer B,shared\n',
      );
      expect(preview.canApply, isFalse);
      expect(preview.errors, hasLength(1));
      expect(preview.errors.single, contains('CSV rows 2 and 3'));
      expect(preview.errors.single, contains('add an id column'));
      expect(preview.errors.single, isNot(contains('csv:')));
    });

    test('warns when a row replaces an existing record with another name', () {
      final first = InventoryImport.csv(
        'cidr,name,routingDomain,customer\n10.0.0.0/16,Customer A,shared,A\n',
      );
      final existing = first.records;
      final same = InventoryImport.csv(
        'cidr,name,routingDomain,customer\n10.0.0.0/16,Customer A,shared,A\n',
        existingRecords: existing,
      );
      expect(same.warnings, isEmpty);
      final renamed = InventoryImport.csv(
        'cidr,name,routingDomain\n10.0.0.0/16,Customer B,shared\n',
        existingRecords: existing,
      );
      final otherCustomer = InventoryImport.csv(
        'cidr,name,routingDomain,customer\n10.0.0.0/16,Customer A,shared,B\n',
        existingRecords: existing,
      );
      for (final preview in [renamed, otherCustomer]) {
        expect(preview.canApply, isTrue);
        expect(preview.warnings.join(), contains('CSV row 2 has no id'));
        expect(preview.warnings.join(), contains('Customer A (10.0.0.0/16'));
        expect(preview.warnings.join(), contains('add ids to keep both'));
      }
    });
  });

  group('CSV formula escaping', () {
    final records = [
      PrefixRecord(
        id: '-dash-id',
        cidr: '10.0.0.0/16',
        name: '=HYPERLINK("http://evil.example","click")',
        routingDomain: '@domain',
        customer: '+Client',
        owner: '-Owner',
        environment: "'=literal quote",
        compartment: "''@two quotes",
        notes: '+cmd|calc',
        source: '=manual',
        verifiedAt: DateTime.utc(2026, 10, 15),
      ),
      const PrefixRecord(
        id: 'tabbed',
        cidr: '2001:db8::/48',
        name: "'plain quote stays",
        routingDomain: 'd',
        notes: '\t=tab first\r\nsecond line',
        source: 'manual',
      ),
    ];

    test('no exported cell starts with a formula character', () {
      final exported = InventoryImport.exportCsv(records);
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\r\n',
      ).convert(exported);
      expect(rows, hasLength(3));
      for (final cell in rows.expand((row) => row)) {
        expect(cell.toString(), isNot(matches(RegExp('^[=+\\-@\t\r]'))),
            reason: '$cell');
      }
      expect(rows[1][2], '\'=HYPERLINK("http://evil.example","click")');
      expect(rows[2][2], "'plain quote stays");
    });

    test('import removes exactly the added guard for a lossless round trip',
        () {
      final preview = InventoryImport.csv(InventoryImport.exportCsv(records));
      expect(preview.errors, isEmpty);
      expect(
        preview.records.map((record) => record.toJson()).toList(),
        records.map((record) => record.toJson()).toList(),
      );
    });
  });

  group('observation time', () {
    test('CSV verifiedAt rejects rollover and is normalized to UTC', () {
      final offset = InventoryImport.csv(
        'cidr,name,routingDomain,verifiedAt\n'
        '10.0.0.0/16,x,d,2026-10-15T12:00:00+02:00\n',
      );
      expect(offset.errors, isEmpty);
      expect(offset.records.single.verifiedAt, DateTime.utc(2026, 10, 15, 10));
      expect(offset.records.single.verifiedAt!.isUtc, isTrue);
      // Zone-less values are the v0.3.0 legacy form, read as local time
      // (see upgrade_compat_test.dart); rollover and garbage are rejected.
      for (final value in [
        '2026-02-30T00:00:00Z',
        '2026-13-45',
        '2026-02-30T10:00:00',
        '2026-10-15 24:00',
      ]) {
        final preview = InventoryImport.csv(
          'cidr,name,routingDomain,verifiedAt\n10.0.0.0/16,x,d,$value\n',
        );
        expect(preview.canApply, isFalse, reason: value);
        expect(preview.errors.single, startsWith('CSV row 2: '));
        expect(preview.errors.single, contains('verifiedAt "$value"'));
      }
    });

    test('backup verifiedAt rejects rolled-over values', () {
      for (final value in ['2026-02-30T10:00:00', '2026-02-30T00:00:00Z']) {
        final preview = InventoryImport.json(
          jsonEncode({
            'format': 'cidr-atlas',
            'version': 1,
            'records': [
              {
                'id': 'x',
                'cidr': '10.0.0.0/16',
                'name': 'x',
                'routingDomain': 'd',
                'verifiedAt': value,
              },
            ],
          }),
          routingDomain: '',
        );
        expect(preview.canApply, isFalse, reason: value);
        expect(preview.errors.single, startsWith('Backup record 1: '));
        expect(preview.errors.single, contains('verifiedAt'));
      }
    });
  });

  group('OCI JSON', () {
    test('equivalent CIDR spellings across alias keys are one prefix', () {
      final preview = InventoryImport.json(
        jsonEncode(ociBundle(vcns: [
          {
            ...vcn,
            'ipv6-cidr-blocks': ['2001:db8:40::/56'],
            'byoipv6CidrBlocks': ['2001:DB8:40::/56', '2001:0db8:40::/56'],
          },
        ], subnets: [])),
        routingDomain: 'corp',
      );
      expect(preview.errors, isEmpty);
      expect(
        preview.records
            .where((record) => Cidr.parse(record.cidr).version == 6)
            .map((record) => record.cidr),
        ['2001:db8:40::/56'],
      );
    });

    test('a truncated raw CLI page is named in the warnings', () {
      const truncated = 'Input is a single truncated OCI CLI page';
      final raw = InventoryImport.json(
        jsonEncode({
          'data': [vcn],
          'opc-next-page': 'AAAA',
        }),
        routingDomain: 'corp',
      );
      final nested = InventoryImport.json(
        jsonEncode({
          'vcns': {
            'data': [vcn],
            'opc-next-page': 'BBBB',
          },
        }),
        routingDomain: 'corp',
      );
      final complete = InventoryImport.json(
        jsonEncode({
          'data': [vcn],
        }),
        routingDomain: 'corp',
      );
      for (final preview in [raw, nested]) {
        expect(preview.canApply, isTrue);
        expect(preview.warnings.join(), contains(truncated));
        expect(preview.warnings.join(), contains('--all'));
      }
      expect(complete.warnings.join(), isNot(contains(truncated)));
    });
  });
}
