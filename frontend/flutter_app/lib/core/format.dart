/// Money, dates and relative times, as the app shows them.
library;

import 'package:intl/intl.dart';

const _symbols = {'INR': '₹', 'USD': r'US$', 'GBP': '£', 'EUR': '€'};

/// Formats integer minor units (paise, cents) without touching doubles.
///
/// INR uses en-IN grouping and shows paise only when there are some: `₹1,20,000`, `₹70.50`.
/// Other currencies group in thousands and always show two decimals: `US$12.50`, `£1,000.00`,
/// `AED 45.00`. Negative amounts read `-₹60`.
String money(int minor, String currency) {
  final isInr = currency == 'INR';
  final abs = minor.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final grouped = isInr ? _groupIndian(whole) : _groupThousands(whole);
  final decimals = (isInr && fraction == 0) ? '' : '.${fraction.toString().padLeft(2, '0')}';
  final prefix = _symbols[currency] ?? '$currency ';
  return '${minor < 0 ? '-' : ''}$prefix$grouped$decimals';
}

/// A price the merchant typed, in minor units: "899" and "899.5" and "1,20,000.00" work. Null when
/// it isn't a valid non-negative amount with at most two decimals. No doubles involved.
int? parseMoneyMinor(String text) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text.replaceAll(',', '').trim());
  if (match == null) return null;
  final whole = int.tryParse(match[1]!);
  if (whole == null) return null;
  return whole * 100 + int.parse((match[2] ?? '').padRight(2, '0'));
}

/// The amount alone, for an edit field: 89950 reads "899.50", 89900 reads "899".
String minorToInput(int minor) {
  final fraction = minor.abs() % 100;
  final whole = minor ~/ 100;
  return fraction == 0 ? '$whole' : '$whole.${fraction.toString().padLeft(2, '0')}';
}

String _groupThousands(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Last three digits, then groups of two: 1,20,000.
String _groupIndian(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);
  final out = StringBuffer();
  for (var i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i) % 2 == 0) out.write(',');
    out.write(head[i]);
  }
  return '$out,$tail';
}

// Times. API timestamps are UTC; these show them in the phone's timezone. Locale-aware calls need
// the locale's date symbols loaded, which GlobalMaterialLocalizations does for the app.

/// `4:12 PM`.
String formatTime(DateTime time, [String? locale]) =>
    DateFormat('h:mm a', locale).format(time.toLocal());

/// `Thu 29 Oct`.
String formatDate(DateTime date, [String? locale]) =>
    DateFormat('EEE d MMM', locale).format(date.toLocal());

/// `Thu 29 Oct, 4:12 PM`.
String formatDateTime(DateTime time, [String? locale]) =>
    '${formatDate(time, locale)}, ${formatTime(time, locale)}';

/// `Today`, `Yesterday`, `Tomorrow`, otherwise `Thu 29 Oct`: chat day separators, order groups.
String dayLabel(DateTime time, {DateTime? now, String? locale}) {
  final local = time.toLocal();
  final difference = daysBetween(now ?? DateTime.now(), local);
  return switch (difference) {
    0 => 'Today',
    -1 => 'Yesterday',
    1 => 'Tomorrow',
    _ => formatDate(local, locale),
  };
}

/// `just now`, `2 min ago`, `3 h ago`, `Yesterday`, `4 days ago`, then `Thu 29 Oct`.
/// A time in the future reads `in 12 min`, `in 3 h`, then the date.
String relativeTime(DateTime time, {DateTime? now, String? locale}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final age = current.difference(local);
  if (age.isNegative) {
    final ahead = -age.inSeconds;
    if (ahead < 60) return 'just now';
    final minutes = -age.inMinutes;
    if (minutes < 60) return 'in $minutes min';
    final hours = -age.inHours;
    if (hours < 24) return 'in $hours h';
    return formatDate(local, locale);
  }
  if (age.inSeconds < 60) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours} h ago';
  final days = -daysBetween(current, local);
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return formatDate(local, locale);
}

// Business dates: calendar days with no time. Take "today" from `Today.businessDate`, which is in
// the shop's timezone, rather than the phone's clock.

/// Reads a business date from the API: "2026-11-05" to local midnight.
DateTime parseBusinessDate(String value) {
  final date = DateTime.parse(value);
  return DateTime(date.year, date.month, date.day);
}

/// The API's form of a day: "2026-11-05".
String businessDateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The calendar day of [date] with the time dropped.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Whole calendar days from [from] to [to]: 1 when [to] is the day after. Safe across daylight
/// saving, because it counts calendar days rather than dividing hours.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// [date] moved by whole calendar days.
DateTime addDays(DateTime date, int days) => DateTime(date.year, date.month, date.day + days);

/// Whether a timestamp falls on a business date, as seen in the phone's timezone. It's an
/// approximation when the phone and the shop are in different timezones.
bool isOnBusinessDate(DateTime time, DateTime businessDate) =>
    daysBetween(time.toLocal(), businessDate) == 0;
