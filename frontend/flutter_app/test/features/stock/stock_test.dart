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
  List<RolloverItem>? rolled;

  @override
  Future<Today> setOpeningStock(List<StockLine> lines) {
    sent.add(lines);
    return super.setOpeningStock(lines);
  }

  @override
  Future<List<StockLine>> parseStockText(String text, {String defaultCurrency = 'INR'}) async {
    if (refuseParse) {
      calls.add('parseStockText');
      throw const ApiException('Could not parse', statusCode: 422);
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
        stockMode: row.stockMode,
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
