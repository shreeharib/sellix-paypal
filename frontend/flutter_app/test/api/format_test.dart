import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/format.dart';

void main() {
  group('money', () {
    test('INR uses en-IN grouping and shows paise only when there are some', () {
      expect(money(12000000, 'INR'), '₹1,20,000');
      expect(money(0, 'INR'), '₹0');
      expect(money(99900, 'INR'), '₹999');
      expect(money(100000, 'INR'), '₹1,000');
      expect(money(10000000000, 'INR'), '₹10,00,00,000');
      expect(money(7050, 'INR'), '₹70.50');
      expect(money(5, 'INR'), '₹0.05');
    });

    test('USD and others always show two decimals', () {
      expect(money(1250, 'USD'), r'US$12.50');
      expect(money(123456789, 'USD'), r'US$1,234,567.89');
      expect(money(100000, 'GBP'), '£1,000.00');
      expect(money(4500, 'AED'), 'AED 45.00');
    });

    test('negative amounts', () {
      expect(money(-12000000, 'INR'), '-₹1,20,000');
      expect(money(-1250, 'USD'), r'-US$12.50');
    });
  });

  group('parseMoneyMinor', () {
    test('reads what a merchant types', () {
      expect(parseMoneyMinor('899'), 89900);
      expect(parseMoneyMinor('899.5'), 89950);
      expect(parseMoneyMinor('899.05'), 89905);
      expect(parseMoneyMinor(' 1,20,000.00 '), 12000000);
      // 19.99 can't be represented exactly as a double: this must not round.
      expect(parseMoneyMinor('19.99'), 1999);
    });

    test('refuses anything else', () {
      expect(parseMoneyMinor(''), isNull);
      expect(parseMoneyMinor('abc'), isNull);
      expect(parseMoneyMinor('-5'), isNull);
      expect(parseMoneyMinor('1.234'), isNull);
    });

    test('minorToInput is its inverse', () {
      expect(minorToInput(89900), '899');
      expect(minorToInput(89950), '899.50');
      expect(minorToInput(5), '0.05');
      expect(parseMoneyMinor(minorToInput(89950)), 89950);
    });
  });

  group('dates', () {
    final now = DateTime(2026, 11, 5, 16, 30);

    test('formatting', () {
      final time = DateTime(2026, 10, 29, 16, 12);
      expect(formatTime(time), '4:12 PM');
      expect(formatDate(time), 'Thu 29 Oct');
      expect(formatDateTime(time), 'Thu 29 Oct, 4:12 PM');
    });

    test('relativeTime', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 2)), now: now), '2 min ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(relativeTime(now.subtract(const Duration(hours: 30)), now: now), 'Yesterday');
      expect(relativeTime(now.subtract(const Duration(days: 4)), now: now), '4 days ago');
      expect(relativeTime(DateTime(2026, 10, 1, 9), now: now), 'Thu 1 Oct');
      expect(relativeTime(now.add(const Duration(minutes: 12)), now: now), 'in 12 min');
      expect(relativeTime(now.add(const Duration(hours: 3)), now: now), 'in 3 h');
    });

    test('relativeTime reads a UTC timestamp correctly', () {
      final utc = now.subtract(const Duration(minutes: 5)).toUtc();
      expect(relativeTime(utc, now: now), '5 min ago');
    });

    test('dayLabel', () {
      expect(dayLabel(DateTime(2026, 11, 5, 1), now: now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 4, 23), now: now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 11, 6), now: now), 'Tomorrow');
      expect(dayLabel(DateTime(2026, 10, 29), now: now), 'Thu 29 Oct');
    });

    test('business dates', () {
      expect(parseBusinessDate('2026-11-05'), DateTime(2026, 11, 5));
      expect(businessDateString(DateTime(2026, 1, 5, 23)), '2026-01-05');
      expect(dateOnly(now), DateTime(2026, 11, 5));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027));
      expect(daysBetween(DateTime(2026, 12, 31, 23), DateTime(2027, 1, 1, 1)), 1);
      expect(isOnBusinessDate(now, DateTime(2026, 11, 5)), isTrue);
      expect(isOnBusinessDate(now, DateTime(2026, 11, 6)), isFalse);
    });
  });
}
