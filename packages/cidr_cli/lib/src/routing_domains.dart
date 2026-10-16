// CIDR Atlas
// Routing-domain hints for commands that scope conflicts by an explicit domain.
// Author: Sergio Farfan <sergio.farfan@gmail.com>

import 'package:cidr_core/cidr_core.dart';

const _shownDomains = 20;

/// Writes a stderr warning when no non-retired record uses [domain].
///
/// Routing domains are exact identifiers, so a mistyped or differently cased
/// domain silently selects an empty conflict scope. The warning names the
/// known domains and any case-insensitive near matches; it never changes the
/// command result or exit code.
void warnUnknownRoutingDomain(
    List<PrefixRecord> records, String domain, StringSink errors) {
  final requested = domain.trim();
  final known = <String>{
    for (final record in records)
      if (record.status != PrefixStatus.retired) record.routingDomain.trim()
  }..remove('');
  if (known.contains(requested)) return;
  if (known.isEmpty) {
    errors.writeln('Warning: routing domain "$requested" has no existing '
        'records; the inventory has no non-retired records in any routing '
        'domain.');
    return;
  }
  final sorted = known.toList()..sort();
  final near = nearRoutingDomains(requested, sorted);
  errors.writeln('Warning: routing domain "$requested" has no existing '
      'non-retired records, so nothing in it can conflict.');
  if (near.isNotEmpty) {
    errors.writeln('  Did you mean: ${near.join(', ')}?');
  }
  final shown = sorted.take(_shownDomains).join(', ');
  final more = sorted.length > _shownDomains
      ? ' and ${sorted.length - _shownDomains} more'
      : '';
  errors.writeln('  Known routing domains: $shown$more.');
}

/// Known domains equal to [requested] ignoring case, or within a small
/// case-insensitive edit distance of it.
List<String> nearRoutingDomains(String requested, Iterable<String> known) {
  final target = requested.trim().toLowerCase();
  final allowed = target.length >= 5 ? 2 : 1;
  return [
    for (final domain in known)
      if (_distance(target, domain.trim().toLowerCase(), allowed) <= allowed)
        domain
  ];
}

/// Levenshtein distance, stopping early once it must exceed [limit].
int _distance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMinimum = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final value = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      current[j] = value;
      if (value < rowMinimum) rowMinimum = value;
    }
    if (rowMinimum > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}
