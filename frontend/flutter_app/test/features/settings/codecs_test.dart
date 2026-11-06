import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/features/settings/hours_codec.dart';
import 'package:sellix_merchant/features/settings/saved_rules.dart';

void main() {
  group('hours', () {
    test('round trips a week with different days and closed dates', () {
      final week = WeekHours.standard()
          .withDay(0, null)
          .withDay(5, const DayHours('10:00 AM', '2:00 PM'))
          .withClosedDates([ClosedDate(DateTime(2026, 11, 8), reason: 'Deepavali'), ClosedDate(DateTime(2026, 12, 25))]);

      final hours = encodeHours(week);
      final closed = encodeClosed(week);
      expect(hours, 'Tue–Fri, 9:00 AM – 8:00 PM; Sat, 10:00 AM – 2:00 PM; Sun, 9:00 AM – 8:00 PM');
      expect(closed, 'Mon; Sun 8 Nov 2026, Deepavali; Fri 25 Dec 2026');

      final back = parseHours(hours, closed);
      expect(back.understood, isTrue);
      expect(back.week.days, week.days);
      expect(back.week.closedDates.map((d) => d.label), ['Sun 8 Nov, Deepavali', 'Fri 25 Dec']);
    });

    test('reads exactly what the onboarding screen writes, and writes it back unchanged', () {
      const hours = 'Tue–Fri, 9:00 AM – 8:00 PM; Sat, 10:00 AM – 6:00 PM';
      const closed = 'Mon; Sun; Sun 8 Nov 2026, Deepavali';
      final parsed = parseHours(hours, closed);
      expect(parsed.understood, isTrue);
      expect(parsed.week.days[0], isNull);
      expect(parsed.week.days[5], const DayHours('10:00 AM', '6:00 PM'));
      expect(parsed.week.days[6], isNull);
      expect(parsed.week.closedDates.single.reason, 'Deepavali');
      expect(encodeHours(parsed.week), hours);
      expect(encodeClosed(parsed.week), closed);
      expect(parseHours(null, 'Mon; Tue; Wed; Thu; Fri; Sat; Sun').week.days.every((d) => d == null), isTrue);
    });

    test('reads what people and the backend example write', () {
      final a = parseHours('Tue–Sun, 9 am – 8 pm', null);
      expect(a.understood, isTrue);
      expect(a.week.days[0], isNull);
      expect(a.week.days[6], const DayHours('9:00 AM', '8:00 PM'));

      final b = parseHours('9 am to 8 pm', 'Mondays');
      expect(b.understood, isTrue);
      expect(b.week.days[0], isNull);
      expect(b.week.days[1], const DayHours('9:00 AM', '8:00 PM'));

      expect(parseHours('Mon, Wed 17:30 to 22:00', null).week.days[2], const DayHours('5:30 PM', '10:00 PM'));
    });

    test('nothing saved reads as open every day, always-closed as no hours', () {
      expect(parseHours(null, null).week.days.every((d) => d != null), isTrue);
      expect(encodeHours(WeekHours(days: List.filled(7, null))), isNull);
    });

    test('reports text it cannot read instead of guessing', () {
      expect(parseHours('Open most evenings', null).understood, isFalse);
      expect(parseHours('9 am to 8 pm', 'every other Monday').understood, isFalse);
      expect(normaliseTime('9'), isNull);
    });

    test('the longest week fits the 200 character answer', () {
      final week = WeekHours(days: [
        for (var i = 0; i < 7; i++) DayHours('1${i % 3}:00 AM', '1${(i + 1) % 3}:00 PM'),
      ]);
      expect(encodeHours(week)!.length, lessThanOrEqualTo(200));
    });

    test('summary for the Profile row', () {
      expect(hoursSummary(const OnboardingAnswers()), 'Not set');
      expect(hoursSummary(const OnboardingAnswers(hours: '9 am to 8 pm')), 'Every day');
      expect(hoursSummary(const OnboardingAnswers(hours: 'Tue to Sun, 9 am to 8 pm')), 'Tue to Sun');
      expect(hoursSummary(const OnboardingAnswers(hours: 'Most evenings')), 'Most evenings');
    });
  });

  group('saved rules', () {
    const profile = '# Shop\n- Open daily.\n## Saved answers\n- Bulk orders: ask the owner.\n- Do you deliver? Yes, nearby.';

    test('reads the section', () {
      final rules = parseSavedRules(profile);
      expect(rules.map((r) => r.question), ['Bulk orders', 'Do you deliver?']);
      expect(rules.map((r) => r.answer), ['ask the owner.', 'Yes, nearby.']);
      expect(parseSavedRules('# Shop'), isEmpty);
      expect(parseSavedRules(null), isEmpty);
    });

    test('an edit keeps the rest of the profile and the other lines exactly', () {
      final rules = parseSavedRules(profile);
      final md = withSavedRules(profile, [SavedRule.written('Sunday?', 'Closed.'), ...rules], fallbackTitle: 'x');
      expect(md, '# Shop\n- Open daily.\n## Saved answers\n- Sunday? Closed.\n- Bulk orders: ask the owner.\n- Do you deliver? Yes, nearby.');
    });

    test('sections after it stay put, and deleting the last rule removes the heading', () {
      const middle = '# Shop\n## Saved answers\n- A: b.\n## Policies\n- x';
      expect(parseSavedRules(middle), hasLength(1));
      expect(withSavedRules(middle, const [], fallbackTitle: 'x'), '# Shop\n## Policies\n- x');
    });

    test('a first rule on an empty shop still has a title', () {
      final md = withSavedRules(null, [SavedRule.written('Q', 'A')], fallbackTitle: 'My Shop');
      expect(md, '# My Shop\n## Saved answers\n- Q: A');
      expect(withSavedRules(null, const [], fallbackTitle: 'My Shop'), '# My Shop');
    });

    test('a line break cannot start a new section', () {
      final rule = SavedRule.written('Q', 'one\n## Policies\ntwo');
      expect(rule.raw, '- Q: one ## Policies two');
    });
  });
}
