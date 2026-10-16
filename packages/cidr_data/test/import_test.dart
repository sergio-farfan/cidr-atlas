// CIDR Atlas
// Import normalization, OCI compatibility, and validation tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'dart:convert';

import 'package:cidr_core/cidr_core.dart';
import 'package:cidr_data/cidr_data.dart';
import 'package:test/test.dart';

const vcn = {
  'id': 'ocid1.vcn.oc1.phx.example',
  'display-name': 'Production VCN',
  'cidr-blocks': ['10.40.0.0/16', '10.41.0.0/16'],
  'cidr-block': '10.40.0.0/16',
  'ipv6-cidr-blocks': ['2001:db8:40::/56'],
  'compartment-id': 'ocid1.compartment.oc1.example',
  'lifecycle-state': 'AVAILABLE',
};
const subnet = {
  'id': 'ocid1.subnet.oc1.phx.example',
  'display-name': 'Private services',
  'vcn-id': 'ocid1.vcn.oc1.phx.example',
  'cidr-block': '10.40.2.0/24',
  'ipv6-cidr-block': '2001:db8:40:2::/64',
};
Map<String, dynamic> ociBundle({
  List<dynamic> vcns = const [vcn],
  List<dynamic> subnets = const [subnet],
}) =>
    {
      'metadata': {
        'tenancy': 'ocid1.tenancy.oc1.example',
        'region': 'us-phoenix-1',
        'coverage': 'selected compartment only',
        'collectedAt': '2026-10-15T18:30:00Z',
      },
      'vcns': vcns,
      'subnets': subnets,
    };

void main() {
  group('empty-result classification', () {
    test('direct empty preview without errors is empty but cannot apply', () {
      final preview = ImportPreview(records: const [], source: 'OCI JSON');

      expect(preview.isEmptyResult, isTrue);
      expect(preview.errors, isEmpty);
      expect(preview.canApply, isFalse);
    });

    test('empty diagnostic alone preserves the raw errors', () {
      final preview = ImportPreview(
        records: const [],
        errors: const [
          ImportPreview.emptyRecordsMessage,
          ImportPreview.emptyRecordsMessage,
        ],
        source: 'OCI JSON',
      );

      expect(preview.isEmptyResult, isTrue);
      expect(preview.errors, [
        'Import contains no prefix records.',
        'Import contains no prefix records.',
      ]);
      expect(preview.canApply, isFalse);
    });

    test('another error excludes empty classification beside the diagnostic',
        () {
      final preview = ImportPreview(
        records: const [],
        errors: const [
          ImportPreview.emptyRecordsMessage,
          'An explicit routing domain is required for OCI JSON imports.',
        ],
        source: 'OCI JSON',
      );

      expect(preview.isEmptyResult, isFalse);
      expect(preview.errors, hasLength(2));
      expect(preview.canApply, isFalse);
    });

    for (final input in [
      jsonEncode(ociBundle(vcns: [], subnets: [])),
      '{"data":[]}',
      '{"vcns":{"data":[]},"subnets":{"data":[]}}',
    ]) {
      test('valid empty OCI collection is classified: $input', () {
        final preview = InventoryImport.json(input, routingDomain: 'corporate');

        expect(preview.isEmptyResult, isTrue);
        expect(preview.records, isEmpty);
        expect(preview.errors, [ImportPreview.emptyRecordsMessage]);
        expect(preview.source, 'OCI JSON');
        expect(preview.warnings, isNotEmpty);
        expect(preview.canApply, isFalse);
      });
    }

    test('header-only CSV is empty but a blank or invalid CSV is not', () {
      final headerOnly = InventoryImport.csv('cidr,name,routingDomain\n');

      expect(headerOnly.isEmptyResult, isTrue);
      expect(headerOnly.errors, [ImportPreview.emptyRecordsMessage]);
      expect(headerOnly.canApply, isFalse);
      for (final input in ['', 'cidr,name\n', 'cidr,name,routngDomain\n']) {
        final invalid = InventoryImport.csv(input);
        expect(invalid.isEmptyResult, isFalse, reason: input);
        expect(invalid.errors, isNotEmpty, reason: input);
        expect(invalid.canApply, isFalse, reason: input);
      }
    });

    test('valid empty backup retains the empty diagnostic and cannot apply',
        () {
      final preview = InventoryImport.json(
        InventoryImport.exportJson([]),
        routingDomain: '',
      );

      expect(preview.isEmptyResult, isTrue);
      expect(preview.records, isEmpty);
      expect(preview.errors, [ImportPreview.emptyRecordsMessage]);
      expect(preview.canApply, isFalse);
    });

    for (final input in [
      '{',
      '[]',
      '{"unrecognized":[]}',
      '{"data":{}}',
      '{"vcns":[],"subnets":{}}',
      '{"vcns":[],"subnets":[],"metadata":"invalid"}',
      '{"format":"other","version":1,"records":[]}',
      '{"format":"cidr-atlas","version":2,"records":[]}',
      '{"format":"cidr-atlas","version":1,"records":{}}',
      '{"format":"cidr-atlas","version":1,"records":[42]}',
    ]) {
      test('invalid JSON is not an empty result: $input', () {
        final preview = InventoryImport.json(input, routingDomain: 'corporate');

        expect(preview.records, isEmpty);
        expect(preview.isEmptyResult, isFalse);
        expect(preview.errors, isNotEmpty);
        expect(preview.canApply, isFalse);
      });
    }

    test('empty OCI collection still requires an explicit routing domain', () {
      final preview = InventoryImport.json('{"data":[]}', routingDomain: ' ');

      expect(preview.records, isEmpty);
      expect(preview.isEmptyResult, isFalse);
      expect(preview.errors.single, contains('routing domain is required'));
      expect(preview.canApply, isFalse);
    });

    test('invalid field type is not an empty result', () {
      final preview = InventoryImport.json(
        jsonEncode({
          'data': [
            {
              'id': 'ocid1.vcn.oc1.phx.example',
              'cidr-blocks': [12],
            },
          ],
        }),
        routingDomain: 'corporate',
      );

      expect(preview.records, isEmpty);
      expect(preview.isEmptyResult, isFalse);
      expect(preview.errors.single, contains('only CIDR strings'));
      expect(preview.canApply, isFalse);
    });

    test('noncanonical CIDR is invalid rather than empty in each format', () {
      final previews = [
        InventoryImport.csv(
          'cidr,name,routingDomain\n10.40.2.7/24,Invalid,corporate',
        ),
        InventoryImport.json(
          jsonEncode({
            'data': [
              {'id': 'ocid1.vcn.oc1.phx.example', 'cidr-block': '10.40.2.7/24'},
            ],
          }),
          routingDomain: 'corporate',
        ),
        InventoryImport.json(
          jsonEncode({
            'format': 'cidr-atlas',
            'version': 1,
            'records': [
              {
                'id': 'invalid',
                'cidr': '10.40.2.7/24',
                'name': 'Invalid',
                'routingDomain': 'corporate',
              },
            ],
          }),
          routingDomain: '',
        ),
      ];

      for (final preview in previews) {
        expect(preview.records, isEmpty, reason: preview.source);
        expect(preview.isEmptyResult, isFalse, reason: preview.source);
        expect(preview.errors, isNotEmpty, reason: preview.source);
        expect(preview.canApply, isFalse, reason: preview.source);
      }
    });

    test('existing inventory validation errors exclude an empty result', () {
      final preview = InventoryImport.csv(
        'cidr,name,routingDomain\n',
        existingRecords: const [
          PrefixRecord(
            id: 'existing',
            cidr: '10.0.0.0/16',
            name: 'Invalid existing prefix',
            routingDomain: '',
          ),
        ],
      );

      expect(preview.records, isEmpty);
      expect(preview.isEmptyResult, isFalse);
      expect(preview.errors, isNotEmpty);
      expect(
          preview.errors, isNot(contains(ImportPreview.emptyRecordsMessage)));
      expect(preview.canApply, isFalse);
    });

    test('nonempty previews are never classified as empty', () {
      final valid = InventoryImport.csv(
        'cidr,name,routingDomain\n10.0.0.0/16,Main,corporate',
      );
      final diagnostic = ImportPreview(
        records: valid.records,
        errors: const [ImportPreview.emptyRecordsMessage],
        source: 'CSV',
      );

      expect(valid.isEmptyResult, isFalse);
      expect(valid.canApply, isTrue);
      expect(diagnostic.isEmptyResult, isFalse);
      expect(diagnostic.canApply, isFalse);
    });

    test('empty-result classification does not permit store apply', () {
      final store = InventoryStore.memory();
      addTearDown(store.close);
      final previews = [
        ImportPreview(records: const [], source: 'OCI JSON'),
        InventoryImport.json('{"data":[]}', routingDomain: 'corporate'),
        InventoryImport.csv('cidr,name,routingDomain\n'),
        InventoryImport.json(
          InventoryImport.exportJson([]),
          routingDomain: '',
        ),
      ];

      for (final preview in previews) {
        expect(preview.isEmptyResult, isTrue, reason: preview.source);
        expect(() => store.applyImport(preview), throwsFormatException);
        expect(store.list(), isEmpty);
        expect(store.history(), isEmpty);
      }
    });
  });

  group('CSV', () {
    test('minimal records get stable ids and defaults', () {
      const input = 'cidr,name,routingDomain\n10.4.0.0/16,Main,corporate\n';
      final preview = InventoryImport.csv(input);
      expect(preview.errors, isEmpty);
      expect(preview.canApply, isTrue);
      expect(preview.records.single.status, PrefixStatus.reserved);
      expect(
        preview.records.single.id,
        InventoryImport.csv(input).records.single.id,
      );
    });

    test('all fields and quoted multiline notes round trip', () {
      final original = PrefixRecord(
        id: 'sample',
        cidr: '2001:db8::/48',
        name: 'Name, "quoted"',
        routingDomain: 'corporate',
        kind: PrefixKind.allocation,
        status: PrefixStatus.planned,
        customer: 'Client',
        tenancy: 'T',
        region: 'R',
        compartment: 'C',
        environment: 'dev',
        owner: 'Person',
        resourceId: 'Resource',
        notes: 'first line\nsecond line, "hello"\r\n third',
        source: 'manual',
        verifiedAt: DateTime.utc(2026, 10, 15),
      );
      final preview = InventoryImport.csv(
        InventoryImport.exportCsv([original]),
      );
      expect(preview.errors, isEmpty);
      expect(preview.records.single.toJson(), original.toJson());
    });

    test('BOM, CRLF and normalized column spellings', () {
      final preview = InventoryImport.csv(
        '\uFEFFCIDR,Name,routing_domain\r\n10.0.0.0/16,Main,corp\r\n',
      );
      expect(preview.canApply, isTrue);
      expect(preview.records.single.routingDomain, 'corp');
    });

    test('rejects typo headers and duplicate columns', () {
      expect(
        InventoryImport.csv('cidr,name,routngDomain\n10.0.0.0/16,x,d').canApply,
        isFalse,
      );
      expect(
        InventoryImport.csv(
          'cidr,name,routingDomain,CIDR\n10.0.0.0/16,x,d,10.0.0.0/16',
        ).errors.join(),
        contains('Duplicate'),
      );
    });

    test('invalid row prevents application of otherwise valid rows', () {
      final preview = InventoryImport.csv(
        'cidr,name,routingDomain\n10.0.0.0/16,x,d\n10.1.2.3/16,y,d',
      );
      expect(preview.records, hasLength(1));
      expect(preview.canApply, isFalse);
      expect(preview.errors.join(), contains('row 3'));
    });

    test(
      'rejects missing fields, extra fields, enum typos and invalid dates',
      () {
        for (final input in [
          'cidr,name\n10.0.0.0/16,x',
          'cidr,name,routingDomain\n10.0.0.0/16,x,d,extra',
          'cidr,name,routingDomain,status\n10.0.0.0/16,x,d,resreved',
          'cidr,name,routingDomain,kind\n10.0.0.0/16,x,d,vcns',
          'cidr,name,routingDomain,verifiedAt\n10.0.0.0/16,x,d,yesterday',
          'cidr,name,routingDomain\n10.0.0.0/16,,d',
          'cidr,name,routingDomain\n10.0.0.0/16,x,',
        ]) {
          expect(InventoryImport.csv(input).canApply, isFalse, reason: input);
        }
      },
    );

    test('detects duplicate ids and broken parent references', () {
      expect(
        InventoryImport.csv(
          'id,cidr,name,routingDomain\nx,10.0.0.0/16,x,d\nx,10.1.0.0/16,y,d',
        ).canApply,
        isFalse,
      );
      expect(
        InventoryImport.csv(
          'cidr,name,routingDomain,parentId\n10.0.0.0/16,x,d,missing',
        ).canApply,
        isFalse,
      );
    });

    test('conflicts remain reviewable', () {
      final preview = InventoryImport.csv(
        'cidr,name,routingDomain\n10.0.0.0/16,x,d\n10.0.0.0/24,y,d',
      );
      expect(preview.canApply, isTrue);
      expect(preview.warnings.join(), contains('conflict'));
    });

    test('empty inputs and header-only files have no applicable records', () {
      expect(InventoryImport.csv('').canApply, isFalse);
      expect(
        InventoryImport.csv('cidr,name,routingDomain\n').canApply,
        isFalse,
      );
    });
  });

  group('JSON backup', () {
    test('preserves identity, metadata, enums and verification timestamp', () {
      final record = PrefixRecord(
        id: 'x',
        cidr: '10.0.0.0/16',
        name: 'Main',
        routingDomain: 'private',
        status: PrefixStatus.retired,
        notes: 'hello',
        verifiedAt: DateTime.utc(2026, 10, 15),
      );
      final preview = InventoryImport.json(
        InventoryImport.exportJson([record]),
        routingDomain: 'ignored',
      );
      expect(preview.canApply, isTrue);
      expect(preview.records.single.toJson(), record.toJson());
    });

    test('rejects newer schema and malformed root/records', () {
      for (final input in [
        '[]',
        '{',
        '{"format":"cidr-atlas","version":2,"records":[]}',
        '{"format":"other","version":1,"records":[]}',
        '{"format":"cidr-atlas","version":1,"records":{}}',
        '{"format":"cidr-atlas","version":1,"records":[42]}',
      ]) {
        expect(
          InventoryImport.json(input, routingDomain: 'd').canApply,
          isFalse,
          reason: input,
        );
      }
    });

    test('invalid record types never silently coerce', () {
      final input = jsonEncode({
        'format': 'cidr-atlas',
        'version': 1,
        'records': [
          {'id': 'x', 'cidr': '10.0.0.0/16', 'name': 12, 'routingDomain': 'd'},
        ],
      });
      expect(
        InventoryImport.json(input, routingDomain: '').errors.join(),
        contains('must be a string'),
      );
    });
  });

  group('OCI JSON', () {
    test('imports multiple VCN CIDRs and linked dual-stack subnets', () {
      final preview = InventoryImport.json(
        jsonEncode(ociBundle()),
        routingDomain: 'enterprise',
      );
      expect(preview.errors, isEmpty);
      expect(preview.records, hasLength(5));
      final vcns = preview.records
          .where((record) => record.kind == PrefixKind.vcn)
          .toList();
      expect(vcns, hasLength(3));
      for (final record in preview.records.where(
        (record) => record.kind == PrefixKind.subnet,
      )) {
        final parent = vcns.singleWhere((vcn) => vcn.id == record.parentId);
        expect(
          Cidr.parse(parent.cidr).contains(Cidr.parse(record.cidr)),
          isTrue,
        );
        expect(record.routingDomain, 'enterprise');
        expect(record.tenancy, 'ocid1.tenancy.oc1.example');
        expect(record.region, 'us-phoenix-1');
        expect(record.verifiedAt, isNotNull);
      }
      expect(InventoryRules.conflicts(preview.records), isEmpty);
      expect(preview.warnings.join(), contains('selected compartment'));
    });

    test('stable identity across repeated imports', () {
      final input = jsonEncode(ociBundle());
      final first = InventoryImport.json(input, routingDomain: 'domain');
      final second = InventoryImport.json(input, routingDomain: 'domain');
      expect(first.records.map((r) => r.id), second.records.map((r) => r.id));
    });

    test('unions OCI subnet IPv4 and VCN BYO IPv6 aliases without duplicates',
        () {
      final importedVcn = {
        ...vcn,
        'byoipv6-cidr-blocks': ['2001:db8:41::/56', '2001:db8:40::/56'],
        'byoipv6CidrBlocks': ['2001:db8:41::/56', '2001:db8:42::/56'],
      };
      final importedSubnet = {
        ...subnet,
        'ipv4-cidr-blocks': ['10.40.2.0/24', '10.40.3.0/24'],
        'ipv4CidrBlocks': ['10.40.4.0/24'],
      };
      final preview = InventoryImport.json(
        jsonEncode(ociBundle(vcns: [importedVcn], subnets: [importedSubnet])),
        routingDomain: 'enterprise',
      );

      expect(preview.errors, isEmpty);
      expect(preview.records, hasLength(9));
      final vcns =
          preview.records.where((r) => r.kind == PrefixKind.vcn).toList();
      final subnets =
          preview.records.where((r) => r.kind == PrefixKind.subnet).toList();
      expect(vcns.map((r) => r.cidr).toSet(), {
        '10.40.0.0/16',
        '10.41.0.0/16',
        '2001:db8:40::/56',
        '2001:db8:41::/56',
        '2001:db8:42::/56',
      });
      expect(subnets.map((r) => r.cidr).toSet(), {
        '10.40.2.0/24',
        '10.40.3.0/24',
        '10.40.4.0/24',
        '2001:db8:40:2::/64',
      });
      expect(vcns.map((r) => r.resourceId).toSet(), {vcn['id']});
      expect(subnets.map((r) => r.resourceId).toSet(), {subnet['id']});
      expect(subnets.map((r) => r.vcnId).toSet(), {vcn['id']});
      expect(preview.records.map((r) => r.id).toSet(), hasLength(9));
    });

    test('observation time comes from source metadata rather than import clock',
        () {
      final preview =
          InventoryImport.json(jsonEncode(ociBundle()), routingDomain: 'corp');
      expect(
          preview.records.every((record) =>
              record.verifiedAt == DateTime.utc(2026, 10, 15, 18, 30)),
          isTrue);
      final unknown = InventoryImport.json(
          jsonEncode({
            'data': [vcn]
          }),
          routingDomain: 'corp');
      expect(
          unknown.records.every((record) => record.verifiedAt == null), isTrue);
      expect(unknown.warnings.join(), contains('observation time is unknown'));
      final invalid = ociBundle();
      (invalid['metadata'] as Map<String, dynamic>)['collectedAt'] =
          'not-a-time';
      expect(
          InventoryImport.json(jsonEncode(invalid), routingDomain: 'corp')
              .canApply,
          isFalse);
    });

    test('raw CLI collection accepted with explicit metadata warning', () {
      final preview = InventoryImport.json(
        jsonEncode({
          'data': [vcn],
        }),
        routingDomain: 'corp',
      );
      expect(preview.canApply, isTrue);
      expect(preview.records, hasLength(3));
      expect(preview.warnings.join(), contains('unknown tenancy or region'));
    });

    test('raw subnet collection retains vcnId without requiring VCN', () {
      final preview = InventoryImport.json(
        jsonEncode({
          'data': [subnet],
        }),
        routingDomain: 'corp',
      );
      expect(preview.canApply, isTrue);
      expect(preview.records, hasLength(2));
      expect(preview.records.first.vcnId, vcn['id']);
      expect(preview.records.first.parentId, isEmpty);
    });

    test('bundle collections can use CLI data wrappers', () {
      final preview = InventoryImport.json(
        jsonEncode({
          'vcns': {
            'data': [vcn],
          },
          'subnets': {
            'data': [subnet],
          },
        }),
        routingDomain: 'corp',
      );
      expect(preview.canApply, isTrue);
      expect(preview.records, hasLength(5));
    });

    test('routing domain is required explicitly', () {
      expect(
        InventoryImport.json(
          jsonEncode(ociBundle()),
          routingDomain: ' ',
        ).canApply,
        isFalse,
      );
    });

    test('malformed resource blocks entire import preview', () {
      final preview = InventoryImport.json(
        jsonEncode(
          ociBundle(
            vcns: [
              vcn,
              {'display-name': 'bad', 'cidr-block': '10.9.0.0/16'},
            ],
          ),
        ),
        routingDomain: 'corp',
      );
      expect(preview.records, isNotEmpty);
      expect(preview.canApply, isFalse);
      expect(preview.errors.join(), contains('id is required'));
    });

    test('invalid or outside subnet CIDR fails preview', () {
      for (final cidr in ['10.40.2.7/24', '172.20.0.0/24']) {
        final preview = InventoryImport.json(
          jsonEncode(
            ociBundle(
              subnets: [
                {...subnet, 'cidr-block': cidr},
              ],
            ),
          ),
          routingDomain: 'corp',
        );
        expect(preview.canApply, isFalse, reason: cidr);
      }
    });

    test('missing CIDRs, wrong collections and invalid types fail preview', () {
      for (final input in [
        {
          'data': [
            {'id': 'x'},
          ],
        },
        {'vcns': {}},
        {'vcns': [], 'metadata': 'bad'},
        {
          'data': [
            {
              ...vcn,
              'cidr-blocks': [12],
            },
          ],
        },
        {'foo': []},
      ]) {
        expect(
          InventoryImport.json(
            jsonEncode(input),
            routingDomain: 'corp',
          ).canApply,
          isFalse,
        );
      }
    });
  });
}
