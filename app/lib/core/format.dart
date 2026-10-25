import 'package:intl/intl.dart';

const _symbols = {'INR': '₹', 'USD': r'$', 'GBP': '£', 'EUR': '€'};

/// Formats integer minor units (paise, cents) the same way the backend does:
/// ₹60, ₹70.50, $19.99.
String formatMoney(int amountMinor, String currency) {
  final whole = amountMinor % 100 == 0;
  final amount = NumberFormat(whole ? '#,##0' : '#,##0.00').format(amountMinor / 100);
  final symbol = _symbols[currency];
  return symbol != null ? '$symbol$amount' : '$currency $amount';
}

String formatTime(DateTime time, String locale) => DateFormat.jm(locale).format(time.toLocal());

String formatDayTime(DateTime time, String locale) =>
    DateFormat.MMMd(locale).add_jm().format(time.toLocal());
