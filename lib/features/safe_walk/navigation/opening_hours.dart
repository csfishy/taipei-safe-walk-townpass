/// Reads the common subset of OpenStreetMap `opening_hours` values:
/// `24/7`, `Mo-Fr 07:00-23:00; Sa,Su 08:00-22:00`, `10:30-22:00`,
/// overnight ranges such as `Mo-Su 18:00-02:00`, and `Su off`.
///
/// Returns null for anything else (public holidays, months, open ends,
/// comments …): unknown hours are never treated as open.
bool? openingHoursOpenAt(String spec, DateTime taipeiTime) {
  final rules = _parse(spec.trim());
  if (rules == null) return null;
  final minute = taipeiTime.hour * 60 + taipeiTime.minute;
  final today = taipeiTime.weekday - 1; // Monday = 0
  final yesterday = (today + 6) % 7;

  // Later rules replace earlier ones for the days they name (OSM semantics).
  _Rule? ruleFor(int day) => rules.lastWhereOrNull((r) => r.days.contains(day));

  final now = ruleFor(today);
  if (now != null) {
    for (final (start, end) in now.ranges) {
      if (end > start ? minute >= start && minute < end : minute >= start) {
        return true;
      }
    }
  }
  final before = ruleFor(yesterday);
  if (before != null) {
    for (final (start, end) in before.ranges) {
      if (end <= start && minute < end) return true;
    }
  }
  return false;
}

/// Open now and still open [margin] later, so the walker does not arrive at a
/// closed door. Null when the hours cannot be read.
bool? openingHoursOpenFor(String spec, DateTime taipeiTime, Duration margin) {
  final now = openingHoursOpenAt(spec, taipeiTime);
  if (now != true) return now;
  return openingHoursOpenAt(spec, taipeiTime.add(margin));
}

/// Wall-clock time in Taipei (UTC+8, no daylight saving).
DateTime taipeiTimeOf(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));

final class _Rule {
  const _Rule(this.days, this.ranges);
  final Set<int> days;

  /// Minutes after midnight; `end <= start` continues past midnight.
  final List<(int, int)> ranges;
}

const _dayNames = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
final _allDays = {0, 1, 2, 3, 4, 5, 6};
final _rulePattern = RegExp(
  r'^(?:([A-Za-z,\- ]+?)\s+)?(off|closed|[0-9:,\- ]+)$',
);
final _range = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$');

List<_Rule>? _parse(String spec) {
  if (spec.isEmpty) return null;
  final rules = <_Rule>[];
  for (final raw in spec.split(';')) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    if (text == '24/7') {
      rules.add(_Rule(_allDays, const [(0, 1440)]));
      continue;
    }
    final m = _rulePattern.firstMatch(text);
    if (m == null) return null;
    final days = m.group(1) == null ? _allDays : _days(m.group(1)!);
    if (days == null) return null;
    final times = m.group(2)!;
    if (times == 'off' || times == 'closed') {
      rules.add(_Rule(days, const []));
      continue;
    }
    final ranges = <(int, int)>[];
    for (final part in times.split(',')) {
      final r = _range.firstMatch(part.trim());
      if (r == null) return null;
      final start = int.parse(r.group(1)!) * 60 + int.parse(r.group(2)!);
      final end = int.parse(r.group(3)!) * 60 + int.parse(r.group(4)!);
      if (start >= 1440 ||
          end > 1440 ||
          int.parse(r.group(2)!) > 59 ||
          int.parse(r.group(4)!) > 59) {
        return null;
      }
      ranges.add((start, end));
    }
    rules.add(_Rule(days, ranges));
  }
  return rules.isEmpty ? null : rules;
}

Set<int>? _days(String text) {
  final days = <int>{};
  for (final part in text.replaceAll(' ', '').split(',')) {
    final ends = part.split('-');
    if (ends.length > 2) return null;
    final a = _dayNames.indexOf(ends.first);
    final b = _dayNames.indexOf(ends.last);
    if (a < 0 || b < 0) return null; // PH, SH, months …
    for (var d = a; ; d = (d + 1) % 7) {
      days.add(d);
      if (d == b) break;
    }
  }
  return days;
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
