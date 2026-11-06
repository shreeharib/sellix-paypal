import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/features/onboarding/ob_answers_text.dart';
import 'package:sellix_merchant/features/onboarding/ob_categories.dart';

void main() {
  test('hours round trip, grouping days with the same times', () {
    final week = {
      ...obDefaultWeek(),
      'Sat': const ObDayHours(open: true, opens: '10:00 AM', closes: '6:00 PM'),
      'Sun': const ObDayHours(open: false),
    };
    final text = obHoursText(week)!;
    expect(text, 'Tue–Fri, 9:00 AM – 8:00 PM; Sat, 10:00 AM – 6:00 PM');
    expect(text.length, lessThanOrEqualTo(200));
    final back = obParseHours(text)!;
    expect(back['Mon']!.open, isFalse);
    expect(back['Wed']!.opens, '9:00 AM');
    expect(back['Sat']!.closes, '6:00 PM');
    expect(back['Sun']!.open, isFalse);
  });

  test('hours in any other form are not guessed at', () {
    expect(obParseHours('Tue-Sun, 9 am - 8 pm'), isNull);
    expect(obParseHours(null), isNull);
  });

  test('closed days and dates round trip', () {
    final dates = [ObClosedDate(DateTime(2026, 11, 8), 'Deepavali'), ObClosedDate(DateTime(2026, 12, 25))];
    final text = obClosedText(obDefaultWeek(), dates)!;
    expect(text, 'Mon; Sun 8 Nov 2026, Deepavali; Fri 25 Dec 2026');
    final back = obParseClosedDates(text);
    expect(back.length, 2);
    expect(back.first.date, DateTime(2026, 11, 8));
    expect(back.first.reason, 'Deepavali');
    expect(back.last.reason, isNull);
    expect(obParseClosedDays(text), ['Mon']);
  });

  test('rule lines replace their own and leave other FAQ lines alone', () {
    const before = 'Do you ship abroad? Yes.\nAsk the shop first: Old.';
    final text = obFaqsWith(before, asks: ['Bulk orders above 25 pieces', 'Discounts'], alone: ['Refunds'])!;
    expect(text, contains('Do you ship abroad? Yes.'));
    expect(text, isNot(contains('Old')));
    expect(obParseAsks(text), ['Bulk orders above 25 pieces', 'Discounts']);
    expect(obParseAlone(text), ['Refunds']);
    expect(obParseBulk(obParseAsks(text), 'Bulk orders'), 25);

    final withLanguages = obFaqsWith(text, languages: ['English', 'Tamil'])!;
    expect(obParseLanguages(withLanguages), ['English', 'Tamil']);
    expect(obParseAsks(withLanguages), hasLength(2));
    expect(obFaqsWith(null, asks: [], alone: []), isNull);
  });

  test('categories read back from what was saved', () {
    expect(obCategoryOf(null), isNull);
    expect(obCategoryOf('Food and sweets')!.id, 'food');
    expect(obCategoryOf('Pet food')!.id, 'other');
  });

  test('UPI IDs', () {
    expect(obUpiPattern.hasMatch('meena@okbank'), isTrue);
    expect(obUpiPattern.hasMatch('meena'), isFalse);
    expect(obUpiPattern.hasMatch('a@b'), isFalse);
  });
}
