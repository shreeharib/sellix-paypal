/// The API keeps hours and rules as free text the agent reads (`OnboardingAnswers`). These turn the
/// onboarding controls into that text and back. Pure, so they are tested on their own.
library;

import 'package:intl/intl.dart';

const obDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class ObDayHours {
  const ObDayHours({required this.open, this.opens = '9:00 AM', this.closes = '8:00 PM'});

  final bool open;
  final String opens;
  final String closes;

  ObDayHours copyWith({bool? open, String? opens, String? closes}) =>
      ObDayHours(open: open ?? this.open, opens: opens ?? this.opens, closes: closes ?? this.closes);
}

class ObClosedDate {
  const ObClosedDate(this.date, [this.reason]);

  final DateTime date;
  final String? reason;

  static final _format = DateFormat('EEE d MMM y', 'en_US');

  String get label {
    final day = _format.format(date);
    return reason == null || reason!.isEmpty ? day : '$day, $reason';
  }

  bool sameDay(ObClosedDate other) =>
      date.year == other.date.year && date.month == other.date.month && date.day == other.date.day;

  static ObClosedDate? parse(String text) {
    final comma = text.indexOf(',');
    final day = (comma < 0 ? text : text.substring(0, comma)).trim();
    final reason = comma < 0 ? null : text.substring(comma + 1).trim();
    try {
      return ObClosedDate(_format.parseStrict(day), reason);
    } on FormatException {
      return null;
    }
  }
}

/// The week as first shown, as in the prototype: closed Monday, 9 to 8 on other days.
Map<String, ObDayHours> obDefaultWeek() => {for (final d in obDays) d: ObDayHours(open: d != 'Mon')};

/// "Tue–Fri, 9:00 AM – 8:00 PM; Sat, 10:00 AM – 6:00 PM". Null when closed all week.
String? obHoursText(Map<String, ObDayHours> week) {
  final parts = <String>[];
  var i = 0;
  while (i < obDays.length) {
    final day = week[obDays[i]]!;
    if (!day.open) {
      i++;
      continue;
    }
    var end = i;
    while (end + 1 < obDays.length) {
      final next = week[obDays[end + 1]]!;
      if (!next.open || next.opens != day.opens || next.closes != day.closes) break;
      end++;
    }
    final days = end == i ? obDays[i] : '${obDays[i]}–${obDays[end]}';
    parts.add('$days, ${day.opens} – ${day.closes}');
    i = end + 1;
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// Reads [obHoursText] back. Null when the text is in another form (typed elsewhere): the caller
/// keeps the default week rather than guessing.
Map<String, ObDayHours>? obParseHours(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final week = {for (final d in obDays) d: const ObDayHours(open: false)};
  final part = RegExp(r'^(\w{3})(?:–(\w{3}))?, (\d{1,2}:\d{2} [AP]M) – (\d{1,2}:\d{2} [AP]M)$');
  for (final raw in text.split(';')) {
    final m = part.firstMatch(raw.trim());
    if (m == null) return null;
    final from = obDays.indexOf(m[1]!);
    final to = m[2] == null ? from : obDays.indexOf(m[2]!);
    if (from < 0 || to < from) return null;
    for (var i = from; i <= to; i++) {
      week[obDays[i]] = ObDayHours(open: true, opens: m[3]!, closes: m[4]!);
    }
  }
  return week;
}

/// Closed days and dates, read by the agent as "Closed ...":
/// "Mon; Sun 8 Nov 2026, Deepavali". Null when there are none.
String? obClosedText(Map<String, ObDayHours> week, List<ObClosedDate> dates) {
  final parts = [
    for (final d in obDays)
      if (!week[d]!.open) d,
    for (final date in dates) date.label,
  ];
  return parts.isEmpty ? null : parts.join('; ');
}

/// The closed dates inside [obClosedText]; closed days come from the hours text.
List<ObClosedDate> obParseClosedDates(String? text) {
  if (text == null) return const [];
  return [
    for (final part in text.split(';'))
      if (!obDays.contains(part.trim())) ?ObClosedDate.parse(part.trim()),
  ];
}

const _askPrefix = 'Ask the shop first: ';
const _alonePrefix = 'Answer without asking the shop: ';
const _langPrefix = 'Customers write in: ';

/// BACKEND GAP: no structured escalation rules or customer languages. They are written as lines in
/// `answers.faqs`, which the agent reads as text; other lines there are left alone.
String? obFaqsWith(String? faqs, {List<String>? asks, List<String>? alone, List<String>? languages}) {
  final others = (faqs ?? '').split('\n').where((line) {
    if (line.trim().isEmpty) return false;
    if (asks != null && (line.startsWith(_askPrefix) || line.startsWith(_alonePrefix))) return false;
    if (languages != null && line.startsWith(_langPrefix)) return false;
    return true;
  }).toList();
  final out = [
    ...others,
    if (asks != null && asks.isNotEmpty) '$_askPrefix${asks.join('; ')}.',
    if (alone != null && alone.isNotEmpty) '$_alonePrefix${alone.join('; ')}.',
    if (languages != null && languages.isNotEmpty) '$_langPrefix${languages.join(', ')}.',
  ];
  return out.isEmpty ? null : out.join('\n');
}

String? _lineAfter(String? faqs, String prefix) {
  for (final line in (faqs ?? '').split('\n')) {
    if (line.startsWith(prefix)) {
      final rest = line.substring(prefix.length).trim();
      return rest.endsWith('.') ? rest.substring(0, rest.length - 1) : rest;
    }
  }
  return null;
}

List<String> obParseAsks(String? faqs) => _lineAfter(faqs, _askPrefix)?.split('; ') ?? const [];

/// The questions turned off. Anything not listed starts on, as after changing what the shop sells.
List<String> obParseAlone(String? faqs) => _lineAfter(faqs, _alonePrefix)?.split('; ') ?? const [];

List<String>? obParseLanguages(String? faqs) => _lineAfter(faqs, _langPrefix)?.split(', ');

String obBulkAsk(String title, int size, String unit) => '$title above $size $unit';

/// The size inside [obBulkAsk], when one of [asks] is the bulk ask.
int? obParseBulk(List<String> asks, String title) {
  for (final ask in asks) {
    final m = RegExp('^${RegExp.escape(title)} above (\\d+) ').firstMatch(ask);
    if (m != null) return int.tryParse(m[1]!);
  }
  return null;
}

/// Closed days inside [obClosedText], for a week with no open hours at all.
List<String> obParseClosedDays(String? text) =>
    [for (final part in (text ?? '').split(';')) if (obDays.contains(part.trim())) part.trim()];

final obUpiPattern = RegExp(r'^[\w.-]{2,}@[a-z0-9.-]{2,}$', caseSensitive: false);
