// CIDR Atlas
// Strict parsing of source observation timestamps.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

final _strictTimestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})'
  r'(?::(\d{2})(?:\.(\d{1,9}))?)?'
  r'(Z|([+-])(\d{2}):(\d{2}))$',
);

/// Parses a source observation time and returns it in UTC.
///
/// The value must be an ISO 8601 date and time, such as
/// `2026-10-15T18:30:00Z` or `2026-10-15T20:30:00.123+02:00`, with an
/// explicit `Z` or `±hh:mm` UTC offset so the instant does not depend on the
/// reading machine's time zone. Seconds and up to nine fractional digits are
/// optional; digits beyond microseconds are truncated. Out-of-range fields
/// such as `2026-02-30`, month 13, or hour 24 are rejected instead of rolling
/// over into a different date.
///
/// Throws a [FormatException] when the value is not accepted.
DateTime parseObservationTime(String value) {
  final text = value.trim();
  final match = _strictTimestamp.firstMatch(text);
  if (match == null) {
    throw FormatException(
      'Observation time must be an ISO 8601 date and time with Z or a '
      '±hh:mm UTC offset, such as 2026-10-15T18:30:00Z.',
      value,
    );
  }
  int field(int group) => int.parse(match.group(group) ?? '0');
  final year = field(1);
  final month = field(2);
  final day = field(3);
  final hour = field(4);
  final minute = field(5);
  final second = field(6);
  final fraction = (match.group(7) ?? '').padRight(6, '0').substring(0, 6);
  final offsetHours = field(10);
  final offsetMinutes = field(11);
  if (!calendarFieldsValid(year, month, day, hour, minute, second) ||
      offsetHours > 23 ||
      offsetMinutes > 59) {
    throw FormatException(
      'Observation time is not a valid calendar date, time, and offset.',
      value,
    );
  }
  final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
  final wallClock = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    0,
    int.parse(fraction),
  );
  return match.group(9) == '-'
      ? wallClock.add(offset)
      : wallClock.subtract(offset);
}

/// Whether the fields survive a round trip through [DateTime.utc] unchanged,
/// which rejects calendar rollover such as February 30 or hour 24.
bool calendarFieldsValid(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
) {
  if (month < 1 || day < 1) return false;
  final value = DateTime.utc(year, month, day, hour, minute, second);
  return value.year == year &&
      value.month == month &&
      value.day == day &&
      value.hour == hour &&
      value.minute == minute &&
      value.second == second;
}

// The extended and basic forms accepted by DateTime.parse.
final _tolerantTimestamp = RegExp(
  r'^([+-]?\d{4,6})-?(\d\d)-?(\d\d)'
  r'(?:[ Tt](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,]\d+)?)?)?'
  r'( ?[zZ]| ?[-+](\d\d)(?::?(\d\d))?)?)?$',
);

/// Reads a timestamp previously written by [DateTime.toIso8601String].
///
/// Values with `Z` or an offset are returned in UTC. Zone-less values keep
/// the legacy meaning of local wall-clock time on the reading machine,
/// because that is how a zone-less local [DateTime] was serialized. Calendar
/// rollover is rejected in both cases; no serialized [DateTime] contains it.
DateTime? tryParseStoredTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final match = _tolerantTimestamp.firstMatch(value.trim());
  if (match == null) return null;
  int field(int group) => int.parse(match.group(group) ?? '0');
  if (!calendarFieldsValid(
        field(1),
        field(2),
        field(3),
        field(4),
        field(5),
        field(6),
      ) ||
      field(8) > 23 ||
      field(9) > 59) {
    return null;
  }
  return parsed;
}
