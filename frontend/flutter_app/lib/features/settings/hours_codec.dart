import 'package:intl/intl.dart';

import '../../core/api/models.dart';

/// Opening hours as a grid on screen and as plain text in `OnboardingAnswers`.
///
/// BACKEND GAP: the API has no structured opening hours. `PATCH /v1/merchant` does not take
/// `opening_hours`, so the week is written as readable text into `answers.hours` and
/// `answers.weekly_off`, and the agent reads those sentences in the shop profile. It is read back
/// by parsing; text someone wrote another way is reported as not understood rather than guessed at.
///
/// Onboarding writes these same two fields (`features/onboarding/ob_answers_text.dart`), and each
/// feature must read what the other wrote, so the written form below has to stay identical to theirs.
const weekDayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _fullDayNames = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

const defaultOpens = '9:00 AM';
const defaultCloses = '8:00 PM';

class DayHours {
  const DayHours(this.opens, this.closes);

  final String opens;
  final String closes;

  @override
  bool operator ==(Object other) => other is DayHours && other.opens == opens && other.closes == closes;

  @override
  int get hashCode => Object.hash(opens, closes);
}

class ClosedDate {
  const ClosedDate(this.date, {this.reason});

  final DateTime date;
  final String? reason;

  /// "Sun 8 Nov, Deepavali".
  String get label {
    final text = DateFormat('EEE d MMM', 'en_US').format(date);
    return reason == null ? text : '$text, $reason';
  }

  bool sameDay(DateTime other) => date.year == other.year && date.month == other.month && date.day == other.day;
}

class WeekHours {
  const WeekHours({required this.days, this.closedDates = const []});

  /// Open every day at the default hours.
  factory WeekHours.standard() =>
      WeekHours(days: List.filled(7, const DayHours(defaultOpens, defaultCloses)));

  /// Monday first. Null is closed.
  final List<DayHours?> days;
  final List<ClosedDate> closedDates;

  WeekHours withDay(int index, DayHours? hours) =>
      WeekHours(days: [...days]..[index] = hours, closedDates: closedDates);

  WeekHours withClosedDates(List<ClosedDate> dates) => WeekHours(days: days, closedDates: dates);
}

class ParsedHours {
  const ParsedHours(this.week, {required this.understood});

  final WeekHours week;

  /// False when the saved text could not be read. Saving the grid then replaces that text.
  final bool understood;
}

/// `answers.hours`: "Tue–Fri, 9:00 AM – 8:00 PM; Sat, 10:00 AM – 6:00 PM". Null when always closed.
String? encodeHours(WeekHours week) {
  final parts = <String>[];
  var i = 0;
  while (i < 7) {
    final hours = week.days[i];
    if (hours == null) {
      i++;
      continue;
    }
    var end = i;
    while (end + 1 < 7 && week.days[end + 1] == hours) {
      end++;
    }
    final days = end == i ? weekDayNames[i] : '${weekDayNames[i]}–${weekDayNames[end]}';
    parts.add('$days, ${hours.opens} – ${hours.closes}');
    i = end + 1;
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// `answers.weekly_off`: "Mon; Thu; Sun 8 Nov 2026, Deepavali". The profile prefixes "Closed".
String? encodeClosed(WeekHours week) {
  final parts = [
    for (var i = 0; i < 7; i++)
      if (week.days[i] == null) weekDayNames[i],
    for (final d in week.closedDates)
      '${DateFormat('EEE d MMM y', 'en_US').format(d.date)}${d.reason == null ? '' : ', ${d.reason}'}',
  ];
  return parts.isEmpty ? null : parts.join('; ');
}

/// Reads back [encodeHours] and [encodeClosed], and the plain forms people write, such as
/// "Tue–Sun, 9 am – 8 pm" or "9 am to 8 pm". Nothing saved reads as open every day.
ParsedHours parseHours(String? hours, String? closed) {
  var understood = true;
  final days = List<DayHours?>.filled(7, const DayHours(defaultOpens, defaultCloses));

  final hoursText = hours?.trim() ?? '';
  if (hoursText.isNotEmpty) {
    days.fillRange(0, 7, null);
    for (final segment in hoursText.split(';')) {
      if (segment.trim().isEmpty) continue;
      final parsed = _parseSegment(segment.trim());
      if (parsed == null) {
        understood = false;
        continue;
      }
      for (final day in parsed.$1) {
        days[day] = parsed.$2;
      }
    }
    if (!understood) days.fillRange(0, 7, const DayHours(defaultOpens, defaultCloses));
  }

  final dates = <ClosedDate>[];
  for (final part in (closed ?? '').split(';')) {
    final text = part.trim();
    if (text.isEmpty) continue;
    final date = _parseDate(text);
    if (date != null) {
      dates.add(date);
      continue;
    }
    final closedDays = _parseDays(text);
    if (closedDays == null) {
      understood = false;
      continue;
    }
    for (final day in closedDays) {
      days[day] = null;
    }
  }
  return ParsedHours(WeekHours(days: days, closedDates: dates), understood: understood);
}

/// "Tue to Sun" for the Profile row.
String hoursSummary(OnboardingAnswers answers) {
  final hours = answers.hours?.trim() ?? '';
  final closed = answers.weeklyOff?.trim() ?? '';
  if (hours.isEmpty && closed.isEmpty) return 'Not set';
  final parsed = parseHours(hours, closed);
  if (!parsed.understood) return hours.isEmpty ? 'Set' : hours;
  final open = [for (var i = 0; i < 7; i++) if (parsed.week.days[i] != null) i];
  if (open.isEmpty) return 'Closed';
  if (open.length == 7) return 'Every day';
  if (open.length == 1) return weekDayNames[open.first];
  final inARow = open.last - open.first == open.length - 1;
  if (inARow) return '${weekDayNames[open.first]} to ${weekDayNames[open.last]}';
  return '${open.length} days a week';
}

const _time = r'\d{1,2}(?:[:.]\d{2})?\s*(?:[ap]\.?m\.?)?';
const _sep = r'(?:to|till|until|–|—|-)';
final _segment = RegExp('^(.*?)[,:\\s]*($_time)\\s*$_sep\\s*($_time)\\s*\$', caseSensitive: false);

(List<int>, DayHours)? _parseSegment(String text) {
  final match = _segment.firstMatch(text);
  if (match == null) return null;
  final opens = normaliseTime(match.group(2)!);
  final closes = normaliseTime(match.group(3)!);
  if (opens == null || closes == null) return null;
  final dayText = match.group(1)!.trim();
  final days = dayText.isEmpty ? <int>[0, 1, 2, 3, 4, 5, 6] : _parseDays(dayText);
  return days == null || days.isEmpty ? null : (days, DayHours(opens, closes));
}

/// "Mon, Wed to Fri". Empty text is no days; null is text it could not read.
List<int>? _parseDays(String text) {
  final lower = text.toLowerCase().trim();
  if (lower.isEmpty || lower == 'none') return const [];
  if (const {'daily', 'every day', 'everyday', 'all days', 'all week'}.contains(lower)) {
    return const [0, 1, 2, 3, 4, 5, 6];
  }
  final days = <int>[];
  for (final part in lower.split(RegExp(r',|&|\band\b'))) {
    final token = part.trim();
    if (token.isEmpty) continue;
    final range = RegExp('^(\\w+)\\s*$_sep\\s*(\\w+)\$').firstMatch(token);
    if (range != null) {
      final from = _dayIndex(range.group(1)!);
      final to = _dayIndex(range.group(2)!);
      if (from == null || to == null) return null;
      for (var d = from;; d = (d + 1) % 7) {
        days.add(d);
        if (d == to) break;
      }
      continue;
    }
    final day = _dayIndex(token);
    if (day == null) return null;
    days.add(day);
  }
  return days;
}

int? _dayIndex(String token) {
  if (token.length < 3) return null;
  final singular = token.endsWith('s') ? token.substring(0, token.length - 1) : token;
  for (var i = 0; i < 7; i++) {
    if (_fullDayNames[i].startsWith(token) || _fullDayNames[i] == singular) return i;
  }
  return null;
}

/// "9 am", "9.30pm" or "17:00" as "h:mm AM". Null when it is not a clear time: a bare "9" is not.
String? normaliseTime(String text) {
  final match = RegExp(r'^(\d{1,2})(?:[:.](\d{2}))?\s*([ap])?\.?(?:m\.?)?$', caseSensitive: false)
      .firstMatch(text.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minuteText = match.group(2);
  final minute = int.parse(minuteText ?? '0');
  final meridiem = match.group(3)?.toLowerCase();
  if (minute > 59) return null;
  final int hour24;
  if (meridiem != null) {
    if (hour < 1 || hour > 12) return null;
    hour24 = hour % 12 + (meridiem == 'p' ? 12 : 0);
  } else {
    if (minuteText == null || hour > 23) return null;
    hour24 = hour;
  }
  final shown = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$shown:${minute.toString().padLeft(2, '0')} ${hour24 >= 12 ? 'PM' : 'AM'}';
}

/// "Sun 8 Nov 2026, Deepavali". The weekday is optional and not trusted: the date decides.
ClosedDate? _parseDate(String text) {
  final match = RegExp(r'^(?:[A-Za-z]{3,} )?(\d{1,2} [A-Za-z]{3,} \d{4})(?:,\s*(.+))?$').firstMatch(text);
  if (match == null) return null;
  try {
    return ClosedDate(DateFormat('d MMM y', 'en_US').parseStrict(match.group(1)!), reason: match.group(2));
  } on FormatException {
    return null;
  }
}
