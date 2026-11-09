import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/api/models.dart';
import 'package:sellix_merchant/core/providers.dart';
import 'package:sellix_merchant/core/router.dart';
import 'package:sellix_merchant/core/theme_mode.dart';
import 'package:sellix_merchant/design/design.dart';
import 'package:sellix_merchant/features/stock/addproduct_screen.dart';
import 'package:sellix_merchant/features/stock/day_stock_screen.dart';
import 'package:sellix_merchant/features/stock/morning_screen.dart';
import 'package:sellix_merchant/features/stock/product_screen.dart';
import 'package:sellix_merchant/features/stock/stock_model.dart';
import 'package:sellix_merchant/features/stock/stock_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_sellix_api.dart';

/// Records the lines sent, which FakeSellixApi doesn't keep, and can refuse parse-stock-text as the
/// backend does for a line with no price.
class _Api extends FakeSellixApi {
  final sent = <List<StockLine>>[];
  bool refuseParse = false;
  bool failSchema = false;
  List<RolloverItem>? rolled;

  /// An older backend, or no network for this one call: the app uses its built-in schema.
  @override
  Future<ProductSchema> productSchema() async {
    if (failSchema) {
      calls.add('productSchema');
      throw const ApiException('Not found', statusCode: 404);
    }
    return super.productSchema();
  }

  @override
  Future<Today> setOpeningStock(List<StockLine> lines) {
    sent.add(lines);
    return super.setOpeningStock(lines);
  }

  @override
  Future<List<StockLine>> parseStockText(String text, {String defaultCurrency = 'INR'}) async {
    if (refuseParse) {
      calls.add('parseStockText');
      // The backend reads "5 gift box 450" and refuses any line with no price.
      final priced = RegExp(r'^(\d+)\s+(.+?)\s+(\d+)$').firstMatch(text.trim());
      if (priced == null) {
        throw const ApiException('Could not parse stock line 1. Expected a count, a name and a price.', statusCode: 422);
      }
      return [
        StockLine(
          product: priced[2]!,
          priceMinor: int.parse(priced[3]!) * 100,
          currency: defaultCurrency,
          quantity: int.parse(priced[1]!),
        ),
      ];
    }
    return super.parseStockText(text, defaultCurrency: defaultCurrency);
  }

  @override
  Future<RolloverResponse> applyRollover(List<RolloverItem> items) {
    rolled = items;
    return super.applyRollover(items);
  }
}

extension on _Api {
  Today get todayForTest => Today(
    businessDate: FakeSellixApi.businessDate,
    agentEnabled: true,
    stock: stock,
    openQuestions: 0,
    ordersAwaitingPayment: 0,
    ordersPaid: 0,
    revenueMinorByCurrency: const {},
  );
}

_Api _api() {
  final api = _Api();
  api.catalog = [
    for (final row in api.stock)
      ProductDetail(
        id: 'product-${row.variantId}',
        name: row.product,
        stockMode: row.stockMode ?? StockMode.daily,
        isActive: true,
        variants: [
          ProductVariantDetail(
            id: row.variantId,
            sku: null,
            name: row.variant,
            priceMinor: row.priceMinor,
            currency: row.currency,
            stockMode: row.stockMode,
            isActive: true,
          ),
        ],
      ),
  ];
  return api;
}

Future<void> _pump(
  WidgetTester tester,
  FakeSellixApi api,
  Widget screen, {
  Map<String, Object> prefsValues = const {},
  Size size = const Size(1200, 4800),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => screen),
      GoRoute(path: Routes.home, builder: (_, _) => const Text('Home screen')),
      GoRoute(path: Routes.stock, builder: (_, _) => const Text('Stock screen')),
      GoRoute(path: Routes.morning, builder: (_, _) => const MorningScreen()),
      GoRoute(
        path: Routes.stockForDay,
        builder: (_, s) => DayStockScreen(
          day: s.uri.queryParameters['date'] == null
              ? null
              : DateTime.parse(s.uri.queryParameters['date']!),
        ),
      ),
      GoRoute(path: Routes.addproduct, builder: (_, s) => AddProductScreen(variantId: s.uri.queryParameters['id'])),
      GoRoute(path: '/product/:id', builder: (_, s) => ProductScreen(s.pathParameters['id']!)),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sellixApiProvider.overrideWithValue(api),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(theme: theme ?? sellixLight, routerConfig: router),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Whether the stock-mode card with this title is the chosen one.
bool _cardOn(WidgetTester tester, String title) =>
    tester.widget<SxChoiceCard>(find.widgetWithText(SxChoiceCard, title)).selected;

/// Whether the chip with this label is on.
bool _chipOn(WidgetTester tester, String label) =>
    tester.widget<SxPickChip>(find.widgetWithText(SxPickChip, label)).selected;

/// Opens the add-product screen, fills the name and price, applies [steps], saves, and returns the
/// stock line sent.
Future<StockLine> _create(
  WidgetTester tester,
  _Api api, {
  List<String> taps = const [],
  String price = '99',
  Future<void> Function()? more,
}) async {
  await _pump(tester, api, const AddProductScreen());
  await _settle(tester);
  await tester.enterText(find.byType(TextField).at(0), 'Gift box');
  await tester.enterText(find.byType(TextField).at(2), price);
  await _settle(tester);
  for (final label in taps) {
    await _tap(tester, label);
  }
  await more?.call();
  await _tap(tester, 'Save product');
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester);
  await tester.pump(const Duration(seconds: 5));
  return api.sent.single.single;
}

/// A label, including on buttons, whose icon is a WidgetSpan beside the text.
Finder _label(String label) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('\uFFFC', '').trim() == label,
);

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(_label(label).last);
  await tester.pump();
  await tester.tap(_label(label).last);
  await _settle(tester);
}

Future<void> _openRow(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await _settle(tester);
}

void main() {
  group('StockScreen', () {
    testWidgets('shows a skeleton, then the ledger', (tester) async {
      final api = _api()..delay = const Duration(milliseconds: 50);
      await _pump(tester, api, const StockScreen());
      await tester.pump();
      expect(find.byType(SxSkeletonList), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await _settle(tester);
      expect(find.text('Item A, small'), findsOneWidget);
      expect(find.text('Stock 10 · Sold 3 · On hold 1'), findsOneWidget);
      expect(find.text('Sold 3'), findsOneWidget);
      expect(find.text('Left from yesterday'), findsOneWidget);
    });

    testWidgets('an empty shop is asked for its first product', (tester) async {
      await _pump(tester, FakeSellixApi.empty(), const StockScreen());
      await _settle(tester);
      expect(find.text('Add your first product'), findsOneWidget);
    });

    testWidgets('an error offers a retry that works', (tester) async {
      final api = _api()..failure = const ApiException('Server down', statusCode: 500);
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      expect(find.text('Try again'), findsOneWidget);
      api.failure = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Item A, small'), findsOneWidget);
    });

    testWidgets('Add stock restocks, and Undo takes the same units off opening', (tester) async {
      final api = _api();
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      await _openRow(tester, 'Item A, small');
      await _tap(tester, 'Add stock');
      await _tap(tester, '+3');
      await _tap(tester, 'Add to stock');
      expect(api.calls, contains('restock'));
      expect(find.text('3 more added. sellix can sell them now.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(api.sent.single.single.quantity, 7);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a counter sale saves, with no Undo the API could not honour', (tester) async {
      final api = _api();
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      await _openRow(tester, 'Item A, small');
      await _tap(tester, 'Sold at shop');
      await _tap(tester, 'Save sale');
      expect(find.text('One is the least you can save.'), findsOneWidget);
      expect(api.calls, isNot(contains('recordCounterSale')));
      await _tap(tester, '+1');
      await _tap(tester, 'Save sale');
      expect(api.calls, contains('recordCounterSale'));
      expect(find.text('1 sale at shop saved.'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Sold out asks first, then has no Undo', (tester) async {
      final api = _api();
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      await _openRow(tester, 'Item A, small');
      await _tap(tester, 'Sold out');
      expect(api.calls, isNot(contains('markSoldOut')));
      expect(find.text('Mark Item A, small sold out?'), findsOneWidget);
      await tester.tap(_label('Sold out').last);
      await _settle(tester);
      expect(api.calls, contains('markSoldOut'));
      expect(find.text('Undo'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Fix count refuses below what is sold, and sends opening less restocks', (tester) async {
      final api = _api();
      final row = api.stock.first;
      api.stock = [
        StockRow(
          variantId: row.variantId,
          product: row.product,
          variant: row.variant,
          priceMinor: row.priceMinor,
          currency: row.currency,
          opening: 3,
          restocked: 2,
          held: 1,
          sold: 2,
          counterSales: 2,
          available: 0,
        ),
      ];
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      await _openRow(tester, 'Item A, small');
      await _tap(tester, 'Fix count');
      await tester.tap(find.bySemanticsLabel('Less').last);
      await _settle(tester);
      expect(find.text('1 on hold and 4 sold. Stock can’t go below 5.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('More').last);
      await _settle(tester);
      await _tap(tester, 'Save count');
      expect(api.sent.single.single.quantity, 4);
      expect(find.text('Stock is now 6.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect(api.sent.last.single.quantity, 3);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('leftovers roll over once on this phone', (tester) async {
      final api = _api();
      api.leftoverItems = [
        ...api.leftoverItems,
        const YesterdayLeftoverItem(
          variantId: 'gone',
          product: 'Fresh bun',
          variant: null,
          priceMinor: 100,
          currency: 'INR',
          leftoverQuantity: 4,
          stockMode: StockMode.daily,
          shelfLifeDays: 1,
        ),
      ];
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      await _tap(tester, 'Left from yesterday');
      expect(find.text('Ended, not for sale'), findsOneWidget);
      expect(find.text('4 left. Same day, past its time.'), findsOneWidget);
      await _tap(tester, 'Confirm counts');
      expect(api.rolled!.single.variantId, FakeIds.variantB);
      expect(api.rolled!.single.rolloverQuantity, 2);
      expect(find.text('2 pieces carried to today.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('leftovers already carried on this phone cannot be carried again', (tester) async {
      final api = _api();
      await _pump(
        tester,
        api,
        const StockScreen(),
        prefsValues: {'stock.carried.2026-01-15': '{"${FakeIds.variantB}":2}'},
      );
      await _settle(tester);
      expect(find.text('2 pieces carried, checked'), findsOneWidget);
      await _tap(tester, 'Left from yesterday');
      expect(find.text('2 pieces carried today'), findsOneWidget);
      await _tap(tester, 'Close');
      expect(api.calls, isNot(contains('applyRollover')));
    });

    testWidgets('Coming days opens the day screen, which saves a count for that day', (tester) async {
      final api = _api();
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      await _tap(tester, 'Coming days');
      expect(api.calls, contains('upcomingStock'));
      await _tap(tester, 'Change Fri stock');
      expect(find.text('What will you have on Fri, 16 Jan?'), findsOneWidget);
      expect(find.text('Item A, small'), findsOneWidget);
      await _tap(tester, 'Save stock for 16 Jan');
      expect(api.calls, contains('setUpcomingStock'));
      expect(api.lastUpcoming!.from, DateTime(2026, 1, 16));
      expect(api.lastUpcoming!.to, DateTime(2026, 1, 16));
      expect(api.lastUpcoming!.lines.single.product, 'Item A');
      expect(find.text('Stock set for Fri, 16 Jan.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a new product for a later day is a one-day item with a last order day', (tester) async {
      final api = _api();
      await _pump(tester, api, const DayStockScreen(day: null));
      await _settle(tester);
      expect(find.text('What will you have on Fri, 16 Jan?'), findsOneWidget);
      await _tap(tester, 'Add another item');
      await _tap(tester, 'New product');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Diwali cake');
      await tester.enterText(fields.at(2), '450');
      await tester.enterText(fields.at(3), '40');
      await _tap(tester, 'Add to the list');
      expect(find.text('Diwali cake'), findsOneWidget);
      expect(find.text('Only on this day'), findsOneWidget);
      expect(find.text('Until the stock runs out'), findsOneWidget);
      await _tap(tester, 'Last day to order');
      await _tap(tester, 'OK');
      expect(find.textContaining('Orders close after it.'), findsOneWidget);
      await _tap(tester, 'Save stock for 16 Jan');
      final sent = api.lastUpcoming!;
      expect(sent.oneDayOnly, isTrue);
      expect(sent.lastOrderDate, DateTime(2026, 1, 15));
      final line = sent.lines.firstWhere((l) => l.product == 'Diwali cake');
      expect(line.priceMinor, 45000);
      expect(line.quantity, 40);
    });

    testWidgets('a one-day item shows on its own day and not on today', (tester) async {
      final api = _api();
      ProductDetail cake(DateTime day) => ProductDetail(
        id: 'cake',
        name: 'Diwali cake',
        stockMode: StockMode.daily,
        isActive: true,
        availableOn: day,
        variants: const [
          ProductVariantDetail(
            id: 'cake-v',
            sku: null,
            name: null,
            priceMinor: 45000,
            currency: 'INR',
            stockMode: StockMode.daily,
            isActive: true,
          ),
        ],
      );
      api.catalog = [...api.catalog, cake(DateTime(2026, 1, 20))];
      await _pump(tester, api, const StockScreen());
      await _settle(tester);
      expect(find.text('Item A, small'), findsOneWidget);
      expect(find.text('Diwali cake'), findsNothing); // not on today's list ...
      await _tap(tester, 'Catalogue');
      expect(find.text('Diwali cake'), findsOneWidget); // ... but in the Catalogue
      expect(find.text('Only 20 Jan'), findsOneWidget);
    });
  });

  group('MorningScreen', () {
    testWidgets('voice is off and says so; typing without a price falls back to the catalogue', (tester) async {
      final api = _api()..refuseParse = true;
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Voice isn’t ready yet. Type your list instead.'), findsOneWidget);
      await _tap(tester, 'Type it');
      await tester.enterText(find.byType(TextField).last, 'nothing here');
      await _tap(tester, 'Make the list');
      expect(find.textContaining('No products found in that.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '8 item b');
      await _tap(tester, 'Make the list');
      expect(api.calls, contains('parseStockText'));
      expect(find.text('sellix found 1 item'), findsOneWidget);
      expect(find.textContaining('you did not list it'), findsOneWidget);
      await _tap(tester, 'Confirm and go live');
      final sent = api.sent.single;
      expect(sent.singleWhere((l) => l.product == 'Item B').quantity, 8);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('Home screen'), findsOneWidget);
      expect(api.calls, isNot(contains('updateMerchant')));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a made-to-order product whose row has no stock type stays under No count needed', (tester) async {
      final api = _api();
      api.catalog = [
        ...api.catalog,
        const ProductDetail(
          id: 'p-cake',
          name: 'Custom cake',
          stockMode: StockMode.madeToOrder,
          isActive: true,
          variants: [
            ProductVariantDetail(id: 'v-cake', sku: null, name: null, priceMinor: 90000, currency: 'INR', isActive: true),
          ],
        ),
      ];
      api.stock = [
        ...api.stock,
        const StockRow(
          variantId: 'v-cake',
          product: 'Custom cake',
          variant: null,
          priceMinor: 90000,
          currency: 'INR',
          opening: 0,
          restocked: 0,
          held: 0,
          sold: 0,
          counterSales: 0,
          available: 0,
        ),
      ];
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Your list: 2 items'), findsOneWidget);
      expect(find.text('No count needed'), findsOneWidget);
      expect(find.text('Custom cake'), findsOneWidget);
    });

    testWidgets('an unchanged list makes no write', (tester) async {
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Your list: 2 items'), findsOneWidget);
      await _tap(tester, 'Confirm and go live');
      expect(api.sent, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('redoing the list keeps carried units in the opening it sends', (tester) async {
      final api = _api();
      await _pump(
        tester,
        api,
        const MorningScreen(),
        prefsValues: {'stock.carried.2026-01-15': '{"${FakeIds.variantB}":2}'},
      );
      await _settle(tester);
      expect(find.text('+2 carried · 5 today'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('More of Item B'));
      await _settle(tester);
      await _tap(tester, 'Confirm and go live');
      expect(api.sent.single.single.quantity, 6);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('+ raises the count, and the count is readable by a screen reader', (tester) async {
      // T4: the user reported that + does nothing on this screen in the web app.
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      int count() => int.parse(tester.getSemantics(find.bySemanticsLabel('Count of Item B')).value);
      final before = count();

      await tester.tap(find.bySemanticsLabel('More of Item B'));
      await _settle(tester);
      expect(count(), before + 1);

      await tester.tap(find.bySemanticsLabel('Less of Item B'));
      await _settle(tester);
      expect(count(), before);
    });

    testWidgets('the stepper inside a stock row lets one step below the row minimum through', (tester) async {
      // 9 Nov web bug: the row passed `min: -1 << 31`, which is +2147483648 on the web (unsigned
      // shifts), so the stepper refused every + in silence. VM tests can't see that, so pin the rule.
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      final steppers = tester.widgetList<SxStepper>(find.byType(SxStepper)).toList();
      expect(steppers, isNotEmpty);
      for (final stepper in steppers) {
        expect(stepper.min, inInclusiveRange(-1, stepperMax));
      }
    });

    testWidgets('error state offers retry', (tester) async {
      final api = _api()..failure = const ApiException('Server down', statusCode: 500);
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('ProductScreen', () {
    testWidgets('joins the ledger to the catalogue; dead ends are labelled', (tester) async {
      final api = _api();
      await _pump(tester, api, const ProductScreen(FakeIds.variantA));
      await _settle(tester);
      expect(find.text('Item A'), findsOneWidget);
      expect(find.text('On sale today'), findsWidgets);
      expect(find.text('Removing products isn’t available yet.'), findsOneWidget);
      expect(find.text('Edit product'), findsOneWidget);
      expect(find.text('This week'), findsNothing);
    });

    testWidgets('taking an item with holds off sale is refused', (tester) async {
      final api = _api();
      await _pump(tester, api, const ProductScreen(FakeIds.variantA));
      await _settle(tester);
      await tester.ensureVisible(find.byType(SxToggle));
      await tester.tap(find.byType(SxToggle));
      await _settle(tester);
      expect(find.text('1 on hold. Finish those orders, then take it off sale.'), findsOneWidget);
      expect(api.sent, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('an unknown variant says so', (tester) async {
      await _pump(tester, _api(), const ProductScreen('nope'));
      await _settle(tester);
      expect(find.text('This product isn’t in your catalogue'), findsOneWidget);
    });
  });

  group('AddProductScreen', () {
    testWidgets('validates, then creates through a stock line', (tester) async {
      final api = _api();
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      await _tap(tester, 'Save product');
      expect(find.text('Name is empty. Add the name customers know it by.'), findsOneWidget);
      expect(find.text('Price is empty. Add a price, because sellix never guesses prices.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Item A');
      await tester.enterText(find.byType(TextField).at(1), 'Small');
      await tester.enterText(find.byType(TextField).at(2), '89.50');
      await _settle(tester);
      await _tap(tester, 'Save product');
      expect(find.textContaining('You already have Item A'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Gift box');
      await _settle(tester);
      await _tap(tester, 'Save product');
      final line = api.sent.single.single;
      expect(line.product, 'Gift box');
      expect(line.priceMinor, 8950);
      expect(line.quantity, 0);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      // The snackbar outlives the form: its Add stock restocks the line just made.
      expect(find.text('Gift box added. Set a count to put it on sale.'), findsOneWidget);
      await tester.tap(find.text('Add stock'));
      await _settle(tester);
      expect(find.text('Add stock: Gift box, small'), findsOneWidget);
    });

    testWidgets('leaving with changes asks first', (tester) async {
      await _pump(tester, _api(), const AddProductScreen());
      await _settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'Gift box');
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Close'));
      await _settle(tester);
      expect(find.text('Leave without saving?'), findsOneWidget);
    });

    testWidgets('edit patches the name and adds aliases by product id', (tester) async {
      final api = _api();
      await _pump(tester, api, const AddProductScreen(variantId: FakeIds.variantA));
      await _settle(tester);
      expect(find.text('Edit product'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Item Z');
      await tester.enterText(find.byType(TextField).last, 'zed');
      await _settle(tester);
      await _tap(tester, 'Save product');
      expect(api.calls, containsAll(['updateProduct', 'addProductAlias']));
      expect(api.sent, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('AddProductScreen and the product schema', () {
    testWidgets('a bakery is asked how it stocks, and the shelf life only for fresh batches', (tester) async {
      final api = _api();
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      expect(api.calls, contains('productSchema'));
      expect(find.text('How do you stock this?'), findsOneWidget);
      for (final mode in [
        'I make fresh batches',
        'I keep stock until it sells',
        'I make it when ordered',
        'Always available',
      ]) {
        expect(find.text(mode), findsOneWidget, reason: mode);
      }
      // The schema's default is chosen, and it asks the shelf life.
      expect(_cardOn(tester, 'I make fresh batches'), isTrue);
      expect(find.text('How long can you sell it?'), findsOneWidget);
      for (final days in ['Same day', '3 days', '1 week', '1 month', 'Custom']) {
        expect(find.text(days), findsOneWidget, reason: days);
      }
      expect(find.text('Doesn’t expire'), findsNothing);
      expect(find.text('Allergens'), findsOneWidget);
      expect(find.text('Ingredients'), findsOneWidget);
      // Keeping stock until it sells: no shelf life, but a count.
      await _tap(tester, 'I keep stock until it sells');
      expect(_cardOn(tester, 'I keep stock until it sells'), isTrue);
      expect(find.text('How long can you sell it?'), findsNothing);
      expect(find.text('How many do you have now?'), findsOneWidget);
      // Made to order: no shelf life and no count.
      await _tap(tester, 'I make it when ordered');
      expect(find.text('How long can you sell it?'), findsNothing);
      expect(find.text('How many do you have now?'), findsNothing);
      await _tap(tester, 'I make fresh batches');
      expect(find.text('How long can you sell it?'), findsOneWidget);
    });

    testWidgets('a dress shop is never asked a shelf life, and has its own details', (tester) async {
      final api = _api()..schema = FakeSchemas.dressShop;
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      expect(find.text('How do you stock this?'), findsOneWidget);
      expect(find.text('I make fresh batches'), findsNothing);
      expect(find.text('Always available'), findsNothing);
      expect(_cardOn(tester, 'I keep stock until it sells'), isTrue);
      expect(find.text('How long can you sell it?'), findsNothing);
      await _tap(tester, 'I make it when ordered');
      expect(find.text('How long can you sell it?'), findsNothing);
      await _tap(tester, 'I keep stock until it sells');
      expect(find.text('How long can you sell it?'), findsNothing);
      // Its own details, not a bakery's.
      expect(find.text('Sizes'), findsOneWidget);
      expect(find.text('XL'), findsOneWidget);
      expect(find.text('Fabric'), findsOneWidget);
      expect(find.text('Allergens'), findsNothing);
      expect(find.text('Ingredients'), findsNothing);
      expect(find.text('Blue kurti'), findsOneWidget);
      expect(find.text('kurta, kurthi'), findsOneWidget);
    });

    testWidgets('a schema with one stock mode does not ask how it is stocked', (tester) async {
      final api = _api()..schema = FakeSchemas.oneMode;
      final line = await _create(
        tester,
        api,
        more: () async {
          expect(find.text('How do you stock this?'), findsNothing);
          expect(find.text('How long can you sell it?'), findsNothing);
        },
      );
      expect(line.stockMode, StockMode.inventory);
      expect(line.shelfLifeDays, isNull);
    });

    testWidgets('fresh batches send the chosen shelf life', (tester) async {
      final line = await _create(tester, _api(), taps: ['1 week']);
      expect(line.stockMode, StockMode.daily);
      expect(line.shelfLifeDays, 7);
      expect(line.product, 'Gift box');
      expect(line.priceMinor, 9900);
    });

    testWidgets('fresh batches send a custom number of days', (tester) async {
      final api = _api();
      final line = await _create(
        tester,
        api,
        taps: ['Custom'],
        more: () async {
          // Name, variant, price, then the days.
          await tester.enterText(find.byType(TextField).at(3), '12');
          await _settle(tester);
          expect(find.text('Leftovers carry to the next day for 12 days.'), findsOneWidget);
        },
      );
      expect(line.stockMode, StockMode.daily);
      expect(line.shelfLifeDays, 12);
    });

    testWidgets('a fresh-batch default is the shop’s usual shelf life', (tester) async {
      final api = _api()
        ..stock = [
          for (final row in _api().stock)
            StockRow(
              variantId: row.variantId,
              product: row.product,
              variant: row.variant,
              priceMinor: row.priceMinor,
              currency: row.currency,
              opening: row.opening,
              restocked: 0,
              held: 0,
              sold: 0,
              counterSales: 0,
              available: row.opening,
              stockMode: StockMode.daily,
              shelfLifeDays: 3,
            ),
        ];
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      expect(find.text('3 days'), findsOneWidget);
      expect(tester.widget<SxPickChip>(find.widgetWithText(SxPickChip, '3 days')).selected, isTrue);
      expect(tester.widget<SxPickChip>(find.widgetWithText(SxPickChip, 'Same day')).selected, isFalse);
    });

    testWidgets('keeping stock until it sells sends no shelf life', (tester) async {
      final line = await _create(tester, _api(), taps: ['I keep stock until it sells']);
      expect(line.stockMode, StockMode.inventory);
      expect(line.shelfLifeDays, isNull);
    });

    testWidgets('made to order and always available send no shelf life; made to order needs no price', (tester) async {
      final line = await _create(tester, _api(), taps: ['I make it when ordered'], price: '');
      expect(line.stockMode, StockMode.madeToOrder);
      expect(line.shelfLifeDays, isNull);
      expect(line.priceMinor, 0);
    });

    testWidgets('always available sends unlimited', (tester) async {
      final line = await _create(tester, _api(), taps: ['Always available']);
      expect(line.stockMode, StockMode.unlimited);
      expect(line.shelfLifeDays, isNull);
    });

    testWidgets('a dress shop sends inventory by default', (tester) async {
      final line = await _create(tester, _api()..schema = FakeSchemas.dressShop);
      expect(line.stockMode, StockMode.inventory);
      expect(line.shelfLifeDays, isNull);
    });

    testWidgets('a bakery’s details are saved in the attributes, under each key', (tester) async {
      final api = _api();
      await _create(
        tester,
        api,
        more: () async {
          await _tap(tester, 'Egg');
          await _tap(tester, 'Milk');
          await tester.enterText(find.byType(TextField).at(3), '  Flour, eggs  ');
          await _settle(tester);
        },
      );
      final saved = api.catalog.singleWhere((p) => p.name == 'Gift box');
      expect(saved.attributes, {
        'allergens': ['Egg', 'Milk'],
        'ingredients': 'Flour, eggs',
      });
      expect(api.calls, contains('updateProduct'));
    });

    testWidgets('a dress shop’s details, including one it adds itself, are saved', (tester) async {
      final api = _api()..schema = FakeSchemas.dressShop;
      await _create(
        tester,
        api,
        more: () async {
          await _tap(tester, 'M');
          await _tap(tester, 'Other');
          await tester.enterText(find.byType(TextField).last, 'XXL');
          await _tap(tester, 'Add detail');
          expect(_chipOn(tester, 'XXL'), isTrue);
          await tester.enterText(find.byType(TextField).at(3), 'Cotton');
          await _settle(tester);
        },
      );
      final saved = api.catalog.singleWhere((p) => p.name == 'Gift box');
      expect(saved.attributes, {
        'sizes': ['M', 'XXL'],
        'fabric': 'Cotton',
      });
    });

    testWidgets('a product with no details makes no attributes call', (tester) async {
      final api = _api();
      await _create(tester, api);
      expect(api.calls, isNot(contains('updateProduct')));
    });

    testWidgets('if the schema can’t be had the built-in one is used, as before', (tester) async {
      final api = _api()..failSchema = true;
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      expect(api.calls, contains('productSchema'));
      expect(find.text('How do you stock this?'), findsOneWidget);
      for (final mode in [
        'I make fresh batches',
        'I keep stock until it sells',
        'I make it when ordered',
        'Always available',
      ]) {
        expect(find.text(mode), findsOneWidget, reason: mode);
      }
      // Today’s behaviour for a new shop: keep until sold, and details by category (not food here).
      expect(_cardOn(tester, 'I keep stock until it sells'), isTrue);
      expect(find.text('How long can you sell it?'), findsNothing);
      await _tap(tester, 'I make fresh batches');
      expect(find.text('How long can you sell it?'), findsOneWidget);
      expect(find.text('Same day'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Allergens'), findsNothing);
    });

    testWidgets('the fallback saves like the schema does', (tester) async {
      final api = _api()..failSchema = true;
      final line = await _create(tester, api, taps: ['I make fresh batches', '3 days']);
      expect(line.stockMode, StockMode.daily);
      expect(line.shelfLifeDays, 3);
    });

    testWidgets('an answer with no stock modes also falls back', (tester) async {
      final api = _api()
        ..schema = const ProductSchema(
          shopType: 'other',
          label: '',
          defaultStockMode: StockMode.inventory,
          stockModes: [],
          shelfLifeOptions: [],
          detailFields: [],
          vocabulary: Vocabulary(stockQuestion: '', exampleProduct: '', aliasExample: ''),
        );
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      expect(find.text('How do you stock this?'), findsOneWidget);
    });

    testWidgets('editing shows the product’s mode and details, and saves only what changed', (tester) async {
      final api = _api();
      await api.updateProduct(
        'product-${FakeIds.variantB}',
        const ProductUpdate(attributes: {'allergens': ['Milk'], 'ingredients': 'Cream', 'other_key': 'kept'}),
      );
      await _pump(tester, api, const AddProductScreen(variantId: FakeIds.variantB));
      await _settle(tester);
      expect(_cardOn(tester, 'I keep stock until it sells'), isTrue);
      expect(find.text('How long can you sell it?'), findsNothing);
      expect(_chipOn(tester, 'Milk'), isTrue);
      expect(_chipOn(tester, 'Egg'), isFalse);
      expect(find.widgetWithText(TextField, 'Cream'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Cream'), 'Fresh cream');
      await _settle(tester);
      await _tap(tester, 'Save product');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
      final saved = api.catalog.singleWhere((p) => p.id == 'product-${FakeIds.variantB}');
      expect(saved.attributes, {
        'allergens': ['Milk'],
        'ingredients': 'Fresh cream',
        'other_key': 'kept',
      });
      expect(api.sent, isEmpty);
    });

    testWidgets('editing a fresh-batch product shows its shelf life, and a change sends mode and days', (tester) async {
      final api = _api();
      await _pump(tester, api, const AddProductScreen(variantId: FakeIds.variantB));
      await _settle(tester);
      await _tap(tester, 'I make fresh batches');
      await _tap(tester, '1 week');
      await _tap(tester, 'Save product');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
      final line = api.sent.single.single;
      expect(line.stockMode, StockMode.daily);
      expect(line.shelfLifeDays, 7);
      expect(line.quantity, 5);
    });

    testWidgets('editing a fresh-batch product reads its current shelf life', (tester) async {
      final api = _api();
      await _pump(tester, api, const AddProductScreen(variantId: FakeIds.variantA));
      await _settle(tester);
      expect(_cardOn(tester, 'I make fresh batches'), isTrue);
      expect(_chipOn(tester, 'Same day'), isTrue);
    });

    testWidgets('a product’s own mode stays visible when its shop type does not list it', (tester) async {
      final api = _api()..schema = FakeSchemas.dressShop;
      await _pump(tester, api, const AddProductScreen(variantId: FakeIds.variantA));
      await _settle(tester);
      // Item A is a fresh-batch product. It keeps showing as one, with its shelf life.
      expect(_cardOn(tester, 'I make fresh batches'), isTrue);
      expect(find.text('How long can you sell it?'), findsOneWidget);
      expect(find.text('I keep stock until it sells'), findsOneWidget);
    });

    testWidgets('a bad custom number of days is refused', (tester) async {
      final api = _api();
      await _pump(tester, api, const AddProductScreen());
      await _settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'Gift box');
      await tester.enterText(find.byType(TextField).at(2), '99');
      await _settle(tester);
      await _tap(tester, 'Custom');
      await tester.enterText(find.byType(TextField).at(3), '');
      await _settle(tester);
      await _tap(tester, 'Save product');
      expect(find.text('Enter 1 to 3650 days.'), findsOneWidget);
      expect(api.sent, isEmpty);
    });

    testWidgets('the product schema shows on the product screen, and a dress shop can’t change a shelf life', (
      tester,
    ) async {
      final api = _api()..schema = FakeSchemas.dressShop;
      await api.updateProduct('product-${FakeIds.variantB}', const ProductUpdate(attributes: {'sizes': ['S', 'M']}));
      await _pump(tester, api, const ProductScreen(FakeIds.variantB));
      await _settle(tester);
      expect(find.text('Sizes'), findsOneWidget);
      expect(find.text('S, M'), findsOneWidget);
      expect(find.text('Fabric'), findsOneWidget);
      expect(find.text('Allergens'), findsNothing);
      await tester.ensureVisible(find.text('Stock stays until sold.'));
      await tester.tap(find.text('Stock stays until sold.'));
      await _settle(tester);
      expect(find.text('How do you stock this?'), findsOneWidget);
      expect(find.text('How long can you sell it?'), findsNothing);
    });

    testWidgets('the product screen’s change sheet asks the shelf life only for fresh batches', (tester) async {
      final api = _api();
      await _pump(tester, api, const ProductScreen(FakeIds.variantB));
      await _settle(tester);
      expect(find.text('Allergens'), findsOneWidget);
      expect(find.text('Ingredients'), findsOneWidget);
      await tester.ensureVisible(find.text('Stock stays until sold.'));
      await tester.tap(find.text('Stock stays until sold.'));
      await _settle(tester);
      expect(find.text('How long can you sell it?'), findsNothing);
      await _tap(tester, 'I make fresh batches');
      expect(find.text('How long can you sell it?'), findsOneWidget);
      await _tap(tester, '3 days');
      await _tap(tester, 'Save');
      final line = api.sent.single.single;
      expect(line.stockMode, StockMode.daily);
      expect(line.shelfLifeDays, 3);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('shop wording from the product schema', () {
    testWidgets('the stock screen asks the schema’s question and uses its example', (tester) async {
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      // The category is not a food one, so the old regex would have said “What’s in stock today?”.
      expect(find.text('What did you make today?'), findsOneWidget);
      await _tap(tester, 'Type it');
      expect(find.text('5 choco lava'), findsOneWidget);
    });

    testWidgets('a dress shop’s question and example', (tester) async {
      final api = _api()..schema = FakeSchemas.dressShop;
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('What’s in stock today?'), findsOneWidget);
      await _tap(tester, 'Type it');
      expect(find.text('5 blue kurti'), findsOneWidget);
    });

    testWidgets('without a schema the wording falls back to the shop’s category', (tester) async {
      final api = _api()..failSchema = true;
      api.answers = const OnboardingAnswers(category: 'Bakery');
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('What did you make today?'), findsOneWidget);
    });

    testWidgets('a product added from Add a missed item shows in Your list when you come back', (tester) async {
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Your list: 2 items'), findsOneWidget);
      await _tap(tester, 'Add a missed item');
      await _tap(tester, 'New product');
      expect(find.text('Save product'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Gift box');
      await tester.enterText(find.byType(TextField).at(2), '120');
      await _settle(tester);
      await _tap(tester, 'Save product');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.text('Save product'), findsNothing);
      expect(find.text('Your list: 3 items'), findsOneWidget);
      expect(find.text('Gift box'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a made-to-order product added the same way shows under No count needed', (tester) async {
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      await _tap(tester, 'Add a missed item');
      await _tap(tester, 'New product');
      await tester.enterText(find.byType(TextField).at(0), 'Custom cake');
      await _settle(tester);
      await _tap(tester, 'I make it when ordered');
      await _tap(tester, 'Save product');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(find.text('Your list: 2 items'), findsOneWidget);
      expect(find.text('Custom cake'), findsOneWidget);
      expect(find.text('No count needed'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Set today’s stock: coming back, and a new item without a price', () {
    testWidgets('the list looks again when you come back from New product, even if the form did not save', (
      tester,
    ) async {
      final api = _api();
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Your list: 2 items'), findsOneWidget);
      await _tap(tester, 'Add a missed item');
      await _tap(tester, 'New product');
      expect(find.text('Save product'), findsOneWidget);
      // The product is made while the form is open (or the form's own refresh did not run).
      await api.setOpeningStock(const [
        StockLine(product: 'Gift box', priceMinor: 12000, quantity: 0, stockMode: StockMode.daily),
      ]);
      await tester.tap(find.bySemanticsLabel('Close'));
      await _settle(tester);
      expect(find.text('Save product'), findsNothing);
      expect(find.text('Your list: 3 items'), findsOneWidget);
      expect(find.text('Gift box'), findsOneWidget);
    });

    testWidgets('the same from the empty first-product screen', (tester) async {
      final api = _Api()
        ..stock = []
        ..catalog = [];
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      expect(find.text('Add your first product'), findsOneWidget);
      await _tap(tester, 'Add product');
      await api.setOpeningStock(const [
        StockLine(product: 'Gift box', priceMinor: 12000, quantity: 2, stockMode: StockMode.daily),
      ]);
      await tester.tap(find.bySemanticsLabel('Close'));
      await _settle(tester);
      expect(find.text('Your list: 1 item'), findsOneWidget);
    });

    testWidgets('a new product typed with no price is asked for its price, not refused with the raw error', (
      tester,
    ) async {
      final api = _api()..refuseParse = true;
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      await _tap(tester, 'Type it');
      await tester.enterText(find.byType(TextField).last, '3 gift box');
      await _tap(tester, 'Make the list');
      expect(find.text('What does Gift box cost? Add the price after the name, like “5 gift box 450”.'), findsOneWidget);
      expect(find.textContaining('Could not parse'), findsNothing);
      expect(find.textContaining('No products found'), findsNothing);
      // The sheet is still open: type the price and it goes through.
      await tester.enterText(find.byType(TextField).last, '3 gift box 450');
      await _tap(tester, 'Make the list');
      expect(find.text('sellix found 1 item'), findsOneWidget);
      await _tap(tester, 'Confirm and go live');
      final line = api.sent.single.singleWhere((l) => l.product == 'gift box');
      expect(line.quantity, 3);
      expect(line.priceMinor, 45000);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a known item beside a new one with no price still asks for the price', (tester) async {
      final api = _api()..refuseParse = true;
      await _pump(tester, api, const MorningScreen());
      await _settle(tester);
      await _tap(tester, 'Type it');
      await tester.enterText(find.byType(TextField).last, '8 item b, 2 lamp, 4 candle');
      await _tap(tester, 'Make the list');
      expect(
        find.text('What do Lamp and Candle cost? Add the price after each name, like “5 lamp 450”.'),
        findsOneWidget,
      );
    });
  });

  group('small dark phone', () {
    for (final (name, screen) in [
      ('stock', const StockScreen()),
      ('morning', const MorningScreen()),
      ('product', const ProductScreen(FakeIds.variantA)),
      ('add', const AddProductScreen()),
    ]) {
      testWidgets('$name lays out without overflow', (tester) async {
        await _pump(tester, _api(), screen, size: const Size(960, 1800), theme: sellixDark);
        await _settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('stock_model', () {
    test('typed text matches names and aliases, longest first', () {
      final items = StockView.join(_api().todayForTest, _api().catalog).items;
      expect(matchStockText('5 item a small and 2 x item b', items), {
        FakeIds.variantA: 5,
        FakeIds.variantB: 2,
      });
      expect(matchStockText('bread 5', items), isEmpty);
    });

    test('a row with no stock type takes the catalogue’s, not a default of daily', () {
      const row = StockRow(
        variantId: 'v-cake',
        product: 'Custom cake',
        variant: null,
        priceMinor: 90000,
        currency: 'INR',
        opening: 0,
        restocked: 0,
        held: 0,
        sold: 0,
        counterSales: 0,
        available: 0,
      );
      final catalog = [
        const ProductDetail(
          id: 'p-cake',
          name: 'Custom cake',
          stockMode: StockMode.madeToOrder,
          isActive: true,
          variants: [
            ProductVariantDetail(
              id: 'v-cake',
              sku: null,
              name: null,
              priceMinor: 90000,
              currency: 'INR',
              isActive: true,
            ),
          ],
        ),
      ];
      final today = Today(
        businessDate: FakeSellixApi.businessDate,
        agentEnabled: true,
        stock: const [row],
        openQuestions: 0,
        ordersAwaitingPayment: 0,
        ordersPaid: 0,
        revenueMinorByCurrency: const {},
      );
      final item = StockView.join(today, catalog).items.single;
      expect(item.stockMode, StockMode.madeToOrder);
      expect(item.counted, isFalse);
      // With nothing else to go on (no catalogue entry), such a row is daily, as before.
      expect(StockView.join(today, const []).items.single.stockMode, StockMode.daily);
      // A row that says its type wins over the catalogue.
      final saysInventory = Today(
        businessDate: FakeSellixApi.businessDate,
        agentEnabled: true,
        stock: [
          StockRow(
            variantId: 'v-cake',
            product: 'Custom cake',
            variant: null,
            priceMinor: 90000,
            currency: 'INR',
            opening: 4,
            restocked: 0,
            held: 0,
            sold: 0,
            counterSales: 0,
            available: 4,
            stockMode: StockMode.inventory,
          ),
        ],
        openQuestions: 0,
        ordersAwaitingPayment: 0,
        ordersPaid: 0,
        revenueMinorByCurrency: const {},
      );
      expect(StockView.join(saysInventory, catalog).items.single.stockMode, StockMode.inventory);
    });

    test('a stock choice maps both ways', () {
      expect(ShelfChoice.of(StockMode.daily, null).c, 'same');
      expect(ShelfChoice.of(StockMode.daily, 7).c, '7');
      expect(ShelfChoice.of(StockMode.daily, 12).c, 'custom');
      // A null shelf_life_days can't clear an old number: inventory still reads as Doesn't expire.
      expect(ShelfChoice.of(StockMode.inventory, 3).c, 'none');
      expect(const ShelfChoice('none').stockMode, StockMode.inventory);
      expect(const ShelfChoice('custom', 0).isValid, isFalse);
      expect(const ShelfChoice('custom', 3650).shelfLifeDays, 3650);
    });
  });
}
