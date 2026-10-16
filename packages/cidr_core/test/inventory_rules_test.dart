// CIDR Atlas
// Hierarchy, routing domain, and allocation tests.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_core/cidr_core.dart';
import 'package:test/test.dart';

PrefixRecord prefix(
  String id,
  String cidr, {
  PrefixKind kind = PrefixKind.vcn,
  PrefixStatus status = PrefixStatus.reserved,
  String domain = 'corporate',
  String parentId = '',
  String resourceId = '',
  String vcnId = '',
  String tenancy = '',
  String region = '',
}) =>
    PrefixRecord(
      id: id,
      cidr: cidr,
      name: id,
      routingDomain: domain,
      kind: kind,
      status: status,
      parentId: parentId,
      resourceId: resourceId,
      vcnId: vcnId,
      tenancy: tenancy,
      region: region,
    );

void main() {
  group('conflict rules', () {
    test('arbitrary numeric containment is a conflict', () {
      final records = [
        prefix('unrelated-vcn', '10.42.0.0/16'),
        prefix('nested-vcn', '10.42.1.0/24'),
      ];
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.conflicts(records), hasLength(1));
      expect(
        InventoryRules.conflicts(records).single.reason,
        contains('without a valid parent'),
      );
    });

    test('requires a valid complete parent chain', () {
      final records = [
        prefix('enterprise', '10.0.0.0/8', kind: PrefixKind.allocation),
        prefix(
          'region',
          '10.32.0.0/12',
          kind: PrefixKind.allocation,
          parentId: 'enterprise',
        ),
        prefix('vcn', '10.42.0.0/16', parentId: 'region'),
        prefix(
          'subnet',
          '10.42.1.0/24',
          kind: PrefixKind.subnet,
          parentId: 'vcn',
        ),
      ];
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.conflicts(records), isEmpty);
      final broken = [
        ...records.take(3),
        records.last.copyWith(parentId: 'missing'),
      ];
      expect(
        InventoryRules.validate(broken).join(),
        contains('does not exist'),
      );
      expect(InventoryRules.conflicts(broken), hasLength(3));
    });

    test('different-kind explicit parents may consume the same full block', () {
      final records = [
        prefix('allocation', '10.42.0.0/16', kind: PrefixKind.allocation),
        prefix('vcn', '10.42.0.0/16', parentId: 'allocation'),
        prefix(
          'subnet',
          '10.42.0.0/16',
          kind: PrefixKind.subnet,
          parentId: 'vcn',
        ),
      ];
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.conflicts(records), isEmpty);
      final sameKind = [
        records.first,
        records[1].copyWith(kind: PrefixKind.allocation),
      ];
      expect(InventoryRules.validate(sameKind).join(), contains('same kind'));
      expect(InventoryRules.conflicts(sameKind), hasLength(1));
    });

    test(
      'OCI resource relationship requires matching domain, tenancy and region',
      () {
        final vcn = prefix(
          'vcn',
          '10.42.0.0/16',
          resourceId: 'ocid-vcn',
          tenancy: 'customer',
          region: 'phx',
        );
        final subnet = prefix(
          'subnet',
          '10.42.1.0/24',
          kind: PrefixKind.subnet,
          vcnId: 'ocid-vcn',
          tenancy: 'customer',
          region: 'phx',
        );
        expect(InventoryRules.conflicts([vcn, subnet]), isEmpty);
        expect(
          InventoryRules.conflicts([
            vcn,
            subnet.copyWith(cidr: '10.42.0.0/16'),
          ]),
          isEmpty,
        );
        expect(
          InventoryRules.conflicts([vcn, subnet.copyWith(vcnId: 'other-vcn')]),
          hasLength(1),
        );
        expect(
          InventoryRules.conflicts([vcn, subnet.copyWith(tenancy: 'other')]),
          hasLength(1),
        );
        expect(
          InventoryRules.conflicts([vcn, subnet.copyWith(region: 'other')]),
          hasLength(1),
        );
        expect(
          InventoryRules.conflicts([
            vcn,
            subnet.copyWith(routingDomain: 'isolated'),
          ]),
          isEmpty,
        );
      },
    );

    test('OCI subnet inherits its VCN explicit allocation ancestry', () {
      final allocation =
          prefix('allocation', '10.0.0.0/8', kind: PrefixKind.allocation);
      final vcn = prefix('vcn', '10.42.0.0/16',
          parentId: 'allocation',
          resourceId: 'ocid-vcn',
          tenancy: 'customer',
          region: 'phx');
      final subnet = prefix('subnet', '10.42.1.0/24',
          kind: PrefixKind.subnet,
          vcnId: 'ocid-vcn',
          tenancy: 'customer',
          region: 'phx');
      expect(InventoryRules.validate([allocation, vcn, subnet]), isEmpty);
      expect(InventoryRules.conflicts([allocation, vcn, subnet]), isEmpty);
      expect(
          InventoryRules.conflicts(
              [allocation, vcn, subnet.copyWith(region: 'iad')]),
          hasLength(2));
      expect(
          InventoryRules.conflicts(
              [allocation, vcn, subnet.copyWith(tenancy: 'other')]),
          hasLength(2));
      final wrongDomain = InventoryRules.conflicts(
          [allocation, vcn.copyWith(routingDomain: 'isolated'), subnet]);
      expect(wrongDomain, hasLength(1));
      expect(wrongDomain.single.first.id, 'allocation');
      expect(wrongDomain.single.second.id, 'subnet');
    });

    test(
        'OCI ancestry requires a valid VCN chain and preserves duplicate VCN conflicts',
        () {
      final allocation =
          prefix('allocation', '10.0.0.0/8', kind: PrefixKind.allocation);
      final vcn = prefix('vcn', '10.42.0.0/16',
          parentId: 'allocation', resourceId: 'ocid-vcn');
      final subnet = prefix('subnet', '10.42.1.0/24',
          kind: PrefixKind.subnet, vcnId: 'ocid-vcn');
      expect(InventoryRules.conflicts([vcn, subnet]), hasLength(1));
      final duplicateVcns = InventoryRules.conflicts(
          [allocation, vcn, vcn.copyWith(id: 'duplicate-vcn'), subnet]);
      expect(duplicateVcns, hasLength(1));
      expect(duplicateVcns.single.first.id, 'vcn');
      expect(duplicateVcns.single.second.id, 'duplicate-vcn');
    });

    test('explicit subnet parent takes precedence over inferred OCI ancestry',
        () {
      final allocation =
          prefix('allocation', '10.0.0.0/8', kind: PrefixKind.allocation);
      final vcn = prefix('vcn', '10.42.0.0/16',
          parentId: 'allocation', resourceId: 'ocid-vcn');
      final subnet = prefix('subnet', '10.42.1.0/24',
          kind: PrefixKind.subnet, parentId: 'allocation', vcnId: 'ocid-vcn');
      final conflicts = InventoryRules.conflicts([allocation, vcn, subnet]);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.first.id, 'vcn');
      expect(conflicts.single.second.id, 'subnet');
    });

    test(
      'overlapping subnet siblings still conflict inside a legitimate VCN',
      () {
        final records = [
          prefix('vcn', '10.0.0.0/16', resourceId: 'vcn-1'),
          prefix(
            'subnet-a',
            '10.0.0.0/24',
            kind: PrefixKind.subnet,
            vcnId: 'vcn-1',
          ),
          prefix(
            'subnet-b',
            '10.0.0.0/25',
            kind: PrefixKind.subnet,
            vcnId: 'vcn-1',
          ),
        ];
        final conflicts = InventoryRules.conflicts(records);
        expect(conflicts, hasLength(1));
        expect(conflicts.single.first.id, 'subnet-a');
        expect(conflicts.single.second.id, 'subnet-b');
      },
    );

    test('retired, isolated, IPv6, and adjacent ranges do not conflict', () {
      final records = [
        prefix('a', '10.0.0.0/24'),
        prefix('adjacent', '10.0.1.0/24'),
        prefix('retired', '10.0.0.0/24', status: PrefixStatus.retired),
        prefix('client-b', '10.0.0.0/24', domain: 'client-b'),
        prefix('ipv6', '::/0'),
      ];
      expect(InventoryRules.conflicts(records), isEmpty);
    });

    test('duplicate ids and broken cycles cannot suppress conflicts', () {
      final cycle = [
        prefix('a', '10.0.0.0/16', kind: PrefixKind.allocation, parentId: 'b'),
        prefix('b', '10.0.0.0/16', kind: PrefixKind.allocation, parentId: 'a'),
      ];
      expect(InventoryRules.validate(cycle).join(), contains('Parent cycle'));
      expect(InventoryRules.conflicts(cycle), hasLength(1));
      final duplicate = [
        prefix('a', '10.0.0.0/16', kind: PrefixKind.allocation),
        prefix('a', '10.0.0.0/16', kind: PrefixKind.allocation),
        prefix('child', '10.0.0.0/24', parentId: 'a'),
      ];
      expect(
        InventoryRules.validate(duplicate).join(),
        contains('Duplicate record id'),
      );
      expect(InventoryRules.validate(duplicate).join(), contains('ambiguous'));
      expect(InventoryRules.conflicts(duplicate), hasLength(3));
    });
  });

  group('structural validation', () {
    test('reports missing identities, invalid CIDRs, and missing parents', () {
      final errors = InventoryRules.validate([
        prefix(
          '',
          '10.0.1.1/24',
          domain: '',
          parentId: 'missing',
        ).copyWith(name: ''),
      ]).join('\n');
      expect(errors, contains('id is required'));
      expect(errors, contains('name is required'));
      expect(errors, contains('routing domain is required'));
      expect(errors, contains('Host bits are set'));
      expect(errors, contains('does not exist'));
    });

    test('rejects containment, cross-domain and kind mismatches', () {
      final parent = prefix('parent', '10.0.0.0/16');
      final subnet = prefix(
        'child',
        '10.0.1.0/24',
        kind: PrefixKind.subnet,
        parentId: 'parent',
      );
      expect(InventoryRules.validate([parent, subnet]), isEmpty);
      expect(
        InventoryRules.validate([parent, subnet.copyWith(cidr: '10.1.0.0/24')])
            .join(),
        contains('not contained'),
      );
      expect(
        InventoryRules.validate([
          parent,
          subnet.copyWith(routingDomain: 'other'),
        ]).join(),
        contains('same routing domain'),
      );
      expect(
        InventoryRules.validate([parent, subnet.copyWith(kind: PrefixKind.vcn)])
            .join(),
        contains('cannot be a parent'),
      );
      expect(
        InventoryRules.validate([
          parent.copyWith(kind: PrefixKind.subnet),
          subnet,
        ]).join(),
        contains('cannot be a parent'),
      );
      expect(
        InventoryRules.validate([parent.copyWith(parentId: 'parent')]).join(),
        contains('own parent'),
      );
    });

    test('explicit VCN links reject contradictory OCI metadata', () {
      final parent = prefix(
        'parent',
        '10.0.0.0/16',
        resourceId: 'vcn-a',
        tenancy: 'a',
        region: 'phx',
      );
      final child = prefix(
        'child',
        '10.0.1.0/24',
        kind: PrefixKind.subnet,
        parentId: 'parent',
        vcnId: 'vcn-b',
        tenancy: 'a',
        region: 'phx',
      );
      expect(
        InventoryRules.validate([parent, child]).join(),
        contains('does not match'),
      );
      expect(
        InventoryRules.validate([
          parent,
          child.copyWith(vcnId: 'vcn-a', tenancy: 'b'),
        ]).join(),
        contains('cross tenancies'),
      );
      expect(
        InventoryRules.validate([
          parent,
          child.copyWith(vcnId: 'vcn-a', region: 'iad'),
        ]).join(),
        contains('cross regions'),
      );
    });
  });

  group('explicit VCN parent and recorded subnet vcnId', () {
    final placeholder = prefix('vcn-a', '10.42.0.0/16');
    final other = prefix('vcn-b', '10.43.0.0/16', resourceId: 'ocid.vcn.b');
    final subnet = prefix(
      'subnet',
      '10.42.1.0/24',
      kind: PrefixKind.subnet,
      parentId: 'vcn-a',
      vcnId: 'ocid.vcn.b',
    );

    const advisory = 'Subnet subnet (10.42.1.0/24) has vcnId ocid.vcn.b, '
        'which names VCN vcn-b (10.43.0.0/16, ocid.vcn.b), but its parent is '
        'the placeholder VCN vcn-a (10.42.0.0/16) without a resource id. '
        'Clear or change the parent of subnet.';

    test('advises, without a validation error, when vcnId names another VCN',
        () {
      final records = [placeholder, other, subnet];
      // A v0.3.0-valid inventory stays savable and importable.
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.advisories(records), [advisory]);
      // The placeholder link keeps its v0.3.0 meaning as a hierarchy.
      expect(InventoryRules.conflicts(records), isEmpty);
    });

    test('advisories filtered by involved ids', () {
      final records = [
        placeholder,
        other,
        subnet,
        prefix('unrelated', '10.50.0.0/16'),
      ];
      for (final id in ['subnet', 'vcn-a', 'vcn-b']) {
        expect(
          InventoryRules.advisories(records, involving: {id}),
          [advisory],
          reason: id,
        );
      }
      expect(InventoryRules.advisories(records, involving: {'unrelated'}),
          isEmpty);
      expect(InventoryRules.advisories(records, involving: {}), isEmpty);
    });

    final unrelatedNamedVcns = {
      'another routing domain': prefix(
        'vcn-b',
        '10.43.0.0/16',
        resourceId: 'ocid.vcn.b',
        domain: 'isolated-lab',
      ),
      'a retired record': prefix(
        'vcn-b',
        '10.43.0.0/16',
        resourceId: 'ocid.vcn.b',
        status: PrefixStatus.retired,
      ),
      'another tenancy': prefix(
        'vcn-b',
        '10.43.0.0/16',
        resourceId: 'ocid.vcn.b',
        tenancy: 'tenancy-b',
      ),
      'another region': prefix(
        'vcn-b',
        '10.43.0.0/16',
        resourceId: 'ocid.vcn.b',
        region: 'iad',
      ),
    };
    for (final MapEntry(key: label, value: named)
        in unrelatedNamedVcns.entries) {
      test('a VCN record from $label does not invalidate the parent', () {
        final located = subnet.copyWith(tenancy: 'tenancy-a', region: 'phx');
        final records = [
          placeholder.copyWith(tenancy: 'tenancy-a', region: 'phx'),
          named,
          located,
        ];
        expect(InventoryRules.validate(records), isEmpty);
        expect(InventoryRules.advisories(records), isEmpty);
        expect(InventoryRules.conflicts(records), isEmpty);
      });
    }

    test('a comparable VCN with empty tenancy and region still contradicts',
        () {
      final records = [
        placeholder,
        other,
        subnet.copyWith(tenancy: 'tenancy-a', region: 'phx'),
      ];
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.advisories(records), hasLength(1));
    });

    test('a retired parent that carries the named OCID stays valid', () {
      final records = [
        prefix(
          'vcn-old',
          '10.42.0.0/16',
          resourceId: 'ocid.vcn.b',
          status: PrefixStatus.retired,
        ),
        prefix('vcn-new', '10.44.0.0/16', resourceId: 'ocid.vcn.b'),
        subnet.copyWith(parentId: 'vcn-old'),
      ];
      expect(InventoryRules.validate(records), isEmpty);
    });

    test('accepts a placeholder parent when no record carries that vcnId', () {
      final records = [placeholder, subnet];
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.advisories(records), isEmpty);
      expect(InventoryRules.conflicts(records), isEmpty);
    });

    test('accepts any block of the named multi-CIDR VCN as parent', () {
      final records = [
        prefix('block-1', '10.40.0.0/16', resourceId: 'ocid.vcn.m'),
        prefix('block-2', '10.41.0.0/16', resourceId: 'ocid.vcn.m'),
        prefix(
          'subnet',
          '10.41.7.0/24',
          kind: PrefixKind.subnet,
          parentId: 'block-2',
          vcnId: 'ocid.vcn.m',
        ),
      ];
      expect(InventoryRules.validate(records), isEmpty);
      expect(InventoryRules.advisories(records), isEmpty);
      expect(InventoryRules.conflicts(records), isEmpty);
    });
  });

  group('free-space planner', () {
    test('zero-limit legacy query validates selection without reading blockers',
        () {
      final parent = Cidr.parse('192.0.2.0/24');
      expect(
          InventoryRules.available(
              parent: parent,
              prefixLength: 28,
              records: [prefix('unparsed', 'malformed')],
              routingDomain: 'corporate',
              limit: 0),
          isEmpty);
      expect(
          () => InventoryRules.available(
              parent: parent,
              prefixLength: 28,
              records: [],
              routingDomain: 'corporate',
              parentId: 'missing',
              limit: 0),
          throwsArgumentError);
    });

    test('legacy query names a malformed blocker instead of skipping it', () {
      List<Cidr> query(List<PrefixRecord> records) => InventoryRules.available(
          parent: Cidr.parse('10.0.0.0/24'),
          prefixLength: 25,
          records: records,
          routingDomain: 'corporate');
      expect(
        () => query([prefix('typo', 'zzz')]),
        throwsA(isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(
              contains('Cannot plan from invalid inventory'), contains('typo')),
        )),
      );
      // Records outside the requested domain or retired are not read.
      expect(
        query([
          prefix('elsewhere', 'zzz', domain: 'lab'),
          prefix('old', 'zzz', status: PrefixStatus.retired),
        ]).map((cidr) => cidr.canonical),
        ['10.0.0.0/25', '10.0.0.128/25'],
      );
    });

    test('finds aligned gaps and ignores only validated selected ancestry', () {
      final results = InventoryRules.available(
        parent: Cidr.parse('10.42.0.0/24'),
        prefixLength: 27,
        routingDomain: 'corporate',
        parentId: 'pool',
        records: [
          prefix('ancestor', '10.0.0.0/8', kind: PrefixKind.allocation),
          prefix('pool', '10.42.0.0/24',
              kind: PrefixKind.allocation, parentId: 'ancestor'),
          prefix('small-partial', '10.42.0.1/32'),
          prefix('blocked', '10.42.0.64/26'),
          prefix('retired', '10.42.0.128/27', status: PrefixStatus.retired),
          prefix('isolated', '10.42.0.160/27', domain: 'client-b'),
        ],
      );
      expect(results.map((network) => network.canonical), [
        '10.42.0.32/27',
        '10.42.0.128/27',
        '10.42.0.160/27',
        '10.42.0.192/27',
        '10.42.0.224/27',
      ]);
    });

    test('unrelated containing VCN blocks the entire selected allocation', () {
      final pool = prefix('pool', '10.42.16.0/20', kind: PrefixKind.allocation);
      final unrelated = prefix('unrelated-vcn', '10.42.0.0/16');
      expect(
          InventoryRules.available(
            parent: Cidr.parse(pool.cidr),
            prefixLength: 24,
            records: [pool, unrelated],
            routingDomain: pool.routingDomain,
            parentId: pool.id,
          ),
          isEmpty);
      expect(
          InventoryRules.available(
            parent: Cidr.parse(pool.cidr),
            prefixLength: 24,
            records: [unrelated],
            routingDomain: pool.routingDomain,
          ),
          isEmpty);
      expect(
          InventoryRules.available(
            parent: Cidr.parse(pool.cidr),
            prefixLength: 24,
            records: [pool, unrelated.copyWith(status: PrefixStatus.retired)],
            routingDomain: pool.routingDomain,
            parentId: pool.id,
            limit: 1,
          ).single.canonical,
          '10.42.16.0/24');
    });

    test('selected parent must exist and match a structurally valid inventory',
        () {
      final pool = prefix('pool', '10.42.0.0/16', kind: PrefixKind.allocation);
      List<Cidr> plan(
              {String id = 'pool',
              String domain = 'corporate',
              String cidr = '10.42.0.0/16',
              List<PrefixRecord>? records}) =>
          InventoryRules.available(
            parent: Cidr.parse(cidr),
            prefixLength: 24,
            records: records ?? [pool],
            routingDomain: domain,
            parentId: id,
          );
      expect(() => plan(id: 'missing'), throwsArgumentError);
      expect(() => plan(domain: 'other'), throwsArgumentError);
      expect(() => plan(cidr: '10.43.0.0/16'), throwsArgumentError);
      expect(() => plan(records: [pool.copyWith(parentId: 'missing')]),
          throwsArgumentError);
      expect(() => plan(records: [pool, pool]), throwsArgumentError);
      expect(plan().first.canonical, '10.42.0.0/24');
    });

    test('equal ranges block and invalid requests are rejected', () {
      final parent = Cidr.parse('10.42.0.0/24');
      expect(
        InventoryRules.available(
          parent: parent,
          prefixLength: 24,
          records: [
            prefix('same', parent.canonical, kind: PrefixKind.allocation),
          ],
          routingDomain: 'corporate',
        ),
        isEmpty,
      );
      expect(
        () => InventoryRules.available(
          parent: parent,
          prefixLength: 23,
          records: [],
          routingDomain: 'corporate',
        ),
        throwsRangeError,
      );
      expect(
        () => InventoryRules.available(
          parent: parent,
          prefixLength: 33,
          records: [],
          routingDomain: 'corporate',
        ),
        throwsRangeError,
      );
      expect(
        () => InventoryRules.available(
          parent: parent,
          prefixLength: 24,
          records: [],
          routingDomain: 'corporate',
          limit: -1,
        ),
        throwsRangeError,
      );
      expect(
        () => InventoryRules.available(
          parent: parent,
          prefixLength: 24,
          records: [],
          routingDomain: '',
        ),
        throwsArgumentError,
      );
      expect(
        InventoryRules.available(
          parent: parent,
          prefixLength: 24,
          records: [],
          routingDomain: 'corporate',
          limit: 0,
        ),
        isEmpty,
      );
    });

    test('selected subnet and retired pools are rejected', () {
      final pool = prefix('pool', '10.42.0.0/24');
      for (final invalid in [
        pool.copyWith(kind: PrefixKind.subnet),
        pool.copyWith(status: PrefixStatus.retired),
      ]) {
        expect(
            () => InventoryRules.available(
                  parent: Cidr.parse(invalid.cidr),
                  prefixLength: 28,
                  records: [invalid],
                  routingDomain: invalid.routingDomain,
                  parentId: invalid.id,
                ),
            throwsArgumentError);
      }
    });

    test('skips enormous IPv6 occupied ranges without address enumeration', () {
      final results = InventoryRules.available(
        parent: Cidr.parse('::/0'),
        prefixLength: 128,
        records: [prefix('half', '::/1')],
        routingDomain: 'corporate',
        limit: 3,
      );
      expect(results.map((network) => network.canonical), [
        '8000::/128',
        '8000::1/128',
        '8000::2/128',
      ]);
      expect(
        InventoryRules.available(
          parent: Cidr.parse('ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe/127'),
          prefixLength: 128,
          records: [
            prefix('last', 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128'),
          ],
          routingDomain: 'corporate',
        ).single.canonical,
        'ffff:ffff:ffff:ffff:ffff:ffff:ffff:fffe/128',
      );
    });

    test(
      'merged overlapping blockers match exhaustive small-network reference',
      () {
        final parent = Cidr.parse('192.0.2.0/24');
        for (var seed = 0; seed < 32; seed++) {
          final records = <PrefixRecord>[];
          for (var i = 0; i < 10; i++) {
            final offset = ((seed * 31 + i * 19) % 64) * 4;
            records.add(prefix('$i', '192.0.2.$offset/30'));
          }
          final expected = <String>[];
          for (var octet = 0; octet < 256; octet += 16) {
            final candidate = Cidr.parse('192.0.2.$octet/28');
            if (!records.any(
              (record) => candidate.overlaps(Cidr.parse(record.cidr)),
            )) {
              expected.add(candidate.canonical);
            }
          }
          final actual = InventoryRules.available(
            parent: parent,
            prefixLength: 28,
            records: records,
            routingDomain: 'corporate',
            limit: 16,
          );
          expect(
            actual.map((network) => network.canonical),
            expected,
            reason: 'seed $seed',
          );
        }
      },
    );
  });
}
