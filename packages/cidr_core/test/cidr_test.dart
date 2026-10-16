import 'package:cidr_core/cidr_core.dart';
import 'package:test/test.dart';

void main() {
  group('strict IPv4', () {
    test('canonicalizes, calculates full ranges, and handles /0', () {
      final subnet = Cidr.parse(' 10.42.16.0/20 ');
      expect(subnet.canonical, '10.42.16.0/20');
      expect(subnet.version, 4);
      expect(subnet.prefixLength, 20);
      expect(subnet.addressCount, BigInt.from(4096));
      expect(subnet.lastAddress - subnet.networkAddress, BigInt.from(4095));
      expect(Cidr.parse('0.0.0.0/0').addressCount, BigInt.one << 32);
      expect(Cidr.parse('255.255.255.255/32').addressCount, BigInt.one);
    });

    test('rejects host bits and suggests the requested network', () {
      expect(
        () => Cidr.parse('10.42.17.0/20'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('10.42.16.0/20'),
          ),
        ),
      );
    });

    test('rejects malformed and ambiguous addresses', () {
      for (final value in [
        '10.0.0.0',
        '10.0.0.0/33',
        '10.0.0.0/-1',
        '10.0.0.0/24/1',
        '256.0.0.0/8',
        '10.0.0/24',
        '010.0.0.0/8',
        '+10.0.0.0/8',
        '10.0.0.0 /8',
        '10.0.0.0/ 8',
        '10.0.0.0/8.0',
        '',
      ]) {
        expect(() => Cidr.parse(value), throwsFormatException, reason: value);
      }
    });

    test(
      'distinguishes containment, equality, adjacency, and disjoint ranges',
      () {
        final parent = Cidr.parse('10.0.0.0/8');
        final child = Cidr.parse('10.42.0.0/16');
        expect(parent.contains(child), isTrue);
        expect(child.contains(parent), isFalse);
        expect(parent.contains(parent), isTrue);
        expect(parent.overlaps(child), isTrue);
        expect(child.overlaps(Cidr.parse('10.43.0.0/16')), isFalse);
        expect(parent.overlaps(Cidr.parse('11.0.0.0/8')), isFalse);
        expect(parent.overlaps(Cidr.parse('::a00:0/104')), isFalse);
      },
    );
  });

  group('strict IPv6', () {
    test('uses RFC 5952 zero compression, lowercase, and leftmost ties', () {
      expect(
        Cidr.parse('2001:0DB8:0000:0000:0001:0000:0000:0001/128').canonical,
        '2001:db8::1:0:0:1/128',
      );
      expect(Cidr.parse('::/0').canonical, '::/0');
      expect(Cidr.parse('2001:db8::/32').canonical, '2001:db8::/32');
      expect(
        Cidr.parse('1:2:3:4:5:6:0:8/128').canonical,
        '1:2:3:4:5:6:0:8/128',
      );
      expect(Cidr.parse('1:2:3:4:5:6::/96').canonical, '1:2:3:4:5:6::/96');
      expect(
        Cidr.parse('::ffff:192.0.2.0/120').canonical,
        '::ffff:c000:200/120',
      );
    });

    test('retains exact 128-bit arithmetic', () {
      final universe = Cidr.parse('::/0');
      final largest = Cidr.parse('ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff/128');
      expect(universe.addressCount, BigInt.one << 128);
      expect(largest.networkAddress, (BigInt.one << 128) - BigInt.one);
      expect(universe.contains(largest), isTrue);
      expect(
        Cidr.parse('2001:db8::/32').contains(Cidr.parse('2001:db8:ffff::/48')),
        isTrue,
      );
      expect(
        Cidr.parse('2001:db8::/33').overlaps(Cidr.parse('2001:db8:8000::/33')),
        isFalse,
      );
    });

    test('rejects invalid groups, compression, zones, and host bits', () {
      for (final value in [
        '2001:db8::1/64',
        '::/129',
        '2001:::db8/32',
        '1::2::3/128',
        '1:2:3:4:5:6:7/128',
        '1:2:3:4:5:6:7:8:9/128',
        '1:2:3:4:5:6:7:8::/128',
        '::gg/128',
        '::10000/128',
        'fe80::%en0/64',
        '::ffff:192.0.2.256/128',
        ':1:2:3:4:5:6:7/128',
        '1:2:3:4:5:6:7:/128',
        '2001:db8::/ -1',
      ]) {
        expect(() => Cidr.parse(value), throwsFormatException, reason: value);
      }
    });
  });

  test(
    'numeric constructor rejects unaligned, negative, or overflowing values',
    () {
      expect(
        () => Cidr.fromNetworkAddress(BigInt.one, 24, 4),
        throwsArgumentError,
      );
      expect(
        () => Cidr.fromNetworkAddress(-BigInt.one, 32, 4),
        throwsArgumentError,
      );
      expect(
        () => Cidr.fromNetworkAddress(BigInt.one << 128, 128, 6),
        throwsArgumentError,
      );
      expect(
        () => Cidr.fromNetworkAddress(BigInt.zero, 33, 4),
        throwsRangeError,
      );
      expect(
        () => Cidr.fromNetworkAddress(BigInt.zero, 1, 5),
        throwsArgumentError,
      );
    },
  );
}
