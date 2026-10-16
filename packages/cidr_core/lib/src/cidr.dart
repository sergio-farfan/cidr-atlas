/// An immutable, canonical IPv4 or IPv6 network.
///
/// Parsing is deliberately strict: host bits are rejected so a reservation
/// cannot silently cover a different network than the caller requested.
final class Cidr {
  Cidr._(this.networkAddress, this.prefixLength, this.version);

  factory Cidr.parse(String input) {
    final parts = input.trim().split('/');
    if (parts.length != 2 || !RegExp(r'^[0-9]+$').hasMatch(parts[1])) {
      throw FormatException(
        'Enter an address and prefix, such as 10.42.0.0/16.',
        input,
      );
    }
    final version = parts[0].contains(':') ? 6 : 4;
    final bits = version == 4 ? 32 : 128;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > bits) {
      throw FormatException(
        'IPv$version prefix must be between 0 and $bits.',
        input,
      );
    }
    final address = version == 4 ? _parseIpv4(parts[0]) : _parseIpv6(parts[0]);
    final hostBits = bits - prefix;
    if (address != ((address >> hostBits) << hostBits)) {
      final network = Cidr._(
        (address >> hostBits) << hostBits,
        prefix,
        version,
      );
      throw FormatException(
        'Host bits are set. Use ${network.canonical}.',
        input,
      );
    }
    return Cidr._(address, prefix, version);
  }

  /// Constructs an aligned network from its unsigned numeric address.
  factory Cidr.fromNetworkAddress(
    BigInt address,
    int prefixLength,
    int version,
  ) {
    if (version != 4 && version != 6) {
      throw ArgumentError.value(version, 'version', 'Must be 4 or 6.');
    }
    final bits = version == 4 ? 32 : 128;
    if (prefixLength < 0 || prefixLength > bits) {
      throw RangeError.range(prefixLength, 0, bits, 'prefixLength');
    }
    if (address.isNegative || address >= (BigInt.one << bits)) {
      throw ArgumentError.value(
        address,
        'address',
        'Outside the IPv$version address space.',
      );
    }
    final hostBits = bits - prefixLength;
    if (address != ((address >> hostBits) << hostBits)) {
      throw ArgumentError.value(
        address,
        'address',
        'Network has host bits set.',
      );
    }
    return Cidr._(address, prefixLength, version);
  }

  final BigInt networkAddress;
  final int prefixLength;
  final int version;

  int get bitLength => version == 4 ? 32 : 128;
  BigInt get addressCount => BigInt.one << (bitLength - prefixLength);
  BigInt get lastAddress => networkAddress + addressCount - BigInt.one;
  String get canonical => '${_formatAddress()}/$prefixLength';

  bool contains(Cidr other) =>
      version == other.version &&
      networkAddress <= other.networkAddress &&
      lastAddress >= other.lastAddress;

  bool overlaps(Cidr other) =>
      version == other.version &&
      networkAddress <= other.lastAddress &&
      other.networkAddress <= lastAddress;

  String _formatAddress() {
    if (version == 4) {
      return [24, 16, 8, 0]
          .map(
            (shift) =>
                ((networkAddress >> shift) & BigInt.from(255)).toString(),
          )
          .join('.');
    }
    final words = List<int>.generate(
      8,
      (i) => ((networkAddress >> ((7 - i) * 16)) & BigInt.from(65535)).toInt(),
    );
    var bestStart = -1;
    var bestLength = 1;
    for (var i = 0; i < words.length;) {
      if (words[i] != 0) {
        i++;
        continue;
      }
      final start = i;
      while (i < words.length && words[i] == 0) {
        i++;
      }
      if (i - start > bestLength) {
        bestStart = start;
        bestLength = i - start;
      }
    }
    if (bestStart < 0) {
      return words.map((word) => word.toRadixString(16)).join(':');
    }
    final before =
        words.take(bestStart).map((word) => word.toRadixString(16)).join(':');
    final after = words
        .skip(bestStart + bestLength)
        .map((word) => word.toRadixString(16))
        .join(':');
    return '$before::$after';
  }

  static BigInt _parseIpv4(String text) {
    final octets = text.split('.');
    if (octets.length != 4) {
      throw FormatException(
        'An IPv4 address must have four decimal octets.',
        text,
      );
    }
    var result = BigInt.zero;
    for (final octet in octets) {
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(octet)) {
        throw FormatException(
          'Invalid IPv4 octet "$octet". Use decimal without leading zeros.',
          text,
        );
      }
      final value = int.parse(octet);
      if (value > 255) {
        throw FormatException('IPv4 octets must be between 0 and 255.', text);
      }
      result = (result << 8) | BigInt.from(value);
    }
    return result;
  }

  static BigInt _parseIpv6(String text) {
    if (text.isEmpty || text.contains('%') || text.contains(':::')) {
      throw FormatException(
        'Invalid IPv6 address. Zone identifiers are not CIDRs.',
        text,
      );
    }
    var normalized = text;
    if (normalized.contains('.')) {
      final lastColon = normalized.lastIndexOf(':');
      if (lastColon < 0) {
        throw FormatException('Invalid embedded IPv4 address.', text);
      }
      final ipv4 = _parseIpv4(normalized.substring(lastColon + 1));
      normalized = '${normalized.substring(0, lastColon + 1)}'
          '${(ipv4 >> 16).toRadixString(16)}:'
          '${(ipv4 & BigInt.from(65535)).toRadixString(16)}';
    }
    final compressed = normalized.split('::');
    if (compressed.length > 2) {
      throw FormatException('An IPv6 address may contain only one ::.', text);
    }
    List<String> segments(String part) => part.isEmpty ? [] : part.split(':');
    final left = segments(compressed[0]);
    final right = compressed.length == 2 ? segments(compressed[1]) : <String>[];
    final count = left.length + right.length;
    if ((compressed.length == 1 && count != 8) ||
        (compressed.length == 2 && count >= 8)) {
      throw FormatException(
        'IPv6 must contain eight groups, optionally compressed with ::.',
        text,
      );
    }
    final words = [
      ...left,
      if (compressed.length == 2) ...List.filled(8 - count, '0'),
      ...right,
    ];
    var result = BigInt.zero;
    for (final word in words) {
      if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(word)) {
        throw FormatException('Invalid IPv6 group "$word".', text);
      }
      result = (result << 16) | BigInt.from(int.parse(word, radix: 16));
    }
    return result;
  }

  @override
  String toString() => canonical;

  @override
  bool operator ==(Object other) =>
      other is Cidr &&
      version == other.version &&
      prefixLength == other.prefixLength &&
      networkAddress == other.networkAddress;

  @override
  int get hashCode => Object.hash(version, prefixLength, networkAddress);
}
