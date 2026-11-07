import '../../core/api/models.dart';
import '../../core/format.dart';

const stepperMax = 999;

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
String units(int n) => plural(n, 'piece', 'pieces');

/// "Name, variant". Sizes and codes keep their case: "Blue, M" reads "blue, M".
String itemName(String product, String? variant) {
  if (variant == null || variant.isEmpty) return product;
  final lower = RegExp(r'^[A-Z][a-z]').hasMatch(variant)
      ? '${variant[0].toLowerCase()}${variant.substring(1)}'
      : variant;
  return '$product, $lower';
}

bool isCounted(String mode) => mode == StockMode.daily || mode == StockMode.inventory;

// BACKEND GAP: a null shelf_life_days means "keep" on PUT /v1/today/stock, so going from 3 days to
// Doesn't expire leaves the old number stored. Inventory always reads as Doesn't expire here.
String shelfLabel(String mode, int? days) {
  if (mode == StockMode.madeToOrder) return 'Made to order';
  if (mode == StockMode.unlimited) return 'Always available';
  if (mode == StockMode.inventory) return 'Doesn’t expire';
  if (days == null || days <= 1) return 'Same day';
  return 'Good for $days days';
}

String noCountWhy(String mode) => mode == StockMode.madeToOrder
    ? 'No count. sellix checks each order with you.'
    : 'No count. sellix can always sell it.';

/// One answer to "How long can you sell it?". [days] is null while the custom field isn't a number.
class ShelfChoice {
  const ShelfChoice(this.c, [this.days = 5]);

  final String c;
  final int? days;

  static const quick = [
    ('same', 'Same day'),
    ('3', '3 days'),
    ('7', '1 week'),
    ('30', '1 month'),
    ('none', 'Doesn’t expire'),
    ('custom', 'Custom'),
  ];
  static const noCount = [('mto', 'Made to order'), ('always', 'Always available')];

  factory ShelfChoice.of(String mode, int? days) {
    if (mode == StockMode.madeToOrder) return const ShelfChoice('mto');
    if (mode == StockMode.unlimited) return const ShelfChoice('always');
    if (mode == StockMode.inventory) return const ShelfChoice('none');
    if (days == null || days <= 1) return const ShelfChoice('same');
    if (const [3, 7, 30].contains(days)) return ShelfChoice('$days', days);
    return ShelfChoice('custom', days);
  }

  bool get isValid => c != 'custom' || (days != null && days! >= 1 && days! <= 3650);
  bool get isNoCount => c == 'mto' || c == 'always';

  String get stockMode => switch (c) {
    'mto' => StockMode.madeToOrder,
    'always' => StockMode.unlimited,
    'none' => StockMode.inventory,
    _ => StockMode.daily,
  };

  int? get shelfLifeDays => switch (c) {
    'mto' || 'always' || 'none' => null,
    'same' => 1,
    'custom' => days,
    _ => int.parse(c),
  };

  bool sameAs(ShelfChoice other) => c == other.c && (c != 'custom' || days == other.days);

  String get line {
    final n = c == 'custom' ? days : int.tryParse(c);
    if (c == 'same' || (c == 'custom' && n == 1)) return 'Leftovers end today. Tomorrow starts at zero.';
    if (c == 'none') return 'Stock stays until sold.';
    if (c == 'mto') return 'No count to keep. sellix checks each order with you.';
    if (c == 'always') return 'No count to keep. sellix can always sell it.';
    if (n == null || n < 1 || n > 3650) return 'Enter the number of days.';
    return 'Leftovers carry to the next day for $n days.';
  }
}

/// A sellable variant: its catalogue facts and today's ledger row, when it has one.
class StockItem {
  const StockItem({
    required this.variantId,
    required this.productId,
    required this.name,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.stockMode,
    required this.shelfLifeDays,
    this.row,
    this.aliases = const [],
    this.attributes = const {},
    this.costPriceMinor,
    this.baseImageUrl,
    this.availableOn,
    this.orderByDate,
  });

  final String variantId;

  /// Null only for a ledger row the catalogue no longer lists.
  final String? productId;
  final String name;
  final String? variant;
  final int priceMinor;
  final String currency;
  final String stockMode;
  final int? shelfLifeDays;
  final StockRow? row;
  final List<ProductAliasDetail> aliases;
  final Map<String, dynamic> attributes;
  final int? costPriceMinor;
  final String? baseImageUrl;

  /// Set: a one-day item, sold on this day only (a festival special for 9 Nov).
  final DateTime? availableOn;

  /// The last day customers can order it.
  final DateTime? orderByDate;

  /// Whether today's list shows it. The Catalogue shows every product; a one-day item for another
  /// day stays off today's list unless it already has a count today.
  bool onListOf(DateTime day) =>
      availableOn == null || daysBetween(availableOn!, day) == 0 || row != null;

  String get label => itemName(name, variant);
  bool get counted => isCounted(stockMode);
  bool get carries => stockMode == StockMode.inventory || (shelfLifeDays ?? 0) > 1;
  bool get live => counted && made > 0;
  int get made => row?.made ?? 0;
  int get opening => row?.opening ?? 0;
  int get restocked => row?.restocked ?? 0;
  int get held => row?.held ?? 0;
  int get soldTotal => row?.soldTotal ?? 0;
  int get available => row?.available ?? 0;

  /// Stock can never go below this: a database check on daily_stock.
  int get floor => held + soldTotal;

  /// The least a full-stock count can be: opening can't go negative, so restocks stay in it.
  int get minMade => floor > restocked ? floor : restocked;

  /// "1 on hold and 2 sold".
  String get floorWhy => [
    if (held > 0) '$held on hold',
    if (soldTotal > 0) '$soldTotal sold',
  ].join(' and ');

  String get shelf => shelfLabel(stockMode, shelfLifeDays);
  String get priceLabel =>
      priceMinor > 0 ? money(priceMinor, currency) : 'Quote per order';

  StockLine line(int quantity, {ShelfChoice? shelf, String? productName, int? price}) => StockLine(
    product: productName ?? name,
    variant: variant,
    priceMinor: price ?? priceMinor,
    currency: currency,
    quantity: quantity,
    stockMode: shelf?.stockMode,
    shelfLifeDays: shelf?.shelfLifeDays,
  );
}

class StockView {
  const StockView(this.today, this.items);

  factory StockView.join(Today today, List<ProductDetail> catalog) {
    final rows = {for (final row in today.stock) row.variantId: row};
    final items = <StockItem>[];
    for (final product in catalog.where((p) => p.isActive)) {
      for (final v in product.variants) {
        final row = rows.remove(v.id);
        if (!v.isActive && row == null) continue;
        items.add(
          StockItem(
            variantId: v.id,
            productId: product.id,
            name: product.name,
            variant: v.name,
            priceMinor: row?.priceMinor ?? v.priceMinor,
            currency: row?.currency ?? v.currency,
            stockMode: row?.stockMode ?? v.stockMode ?? product.stockMode,
            shelfLifeDays: row?.shelfLifeDays ?? v.shelfLifeDays ?? product.shelfLifeDays,
            row: row,
            aliases: product.aliases,
            attributes: product.attributes,
            costPriceMinor: v.costPriceMinor,
            baseImageUrl: product.baseImageUrl,
            availableOn: product.availableOn,
            orderByDate: product.orderByDate,
          ),
        );
      }
    }
    for (final row in rows.values) {
      items.add(
        StockItem(
          variantId: row.variantId,
          productId: null,
          name: row.product,
          variant: row.variant,
          priceMinor: row.priceMinor,
          currency: row.currency,
          stockMode: row.stockMode,
          shelfLifeDays: row.shelfLifeDays,
          row: row,
        ),
      );
    }
    return StockView(today, items);
  }

  final Today today;
  final List<StockItem> items;

  /// Today's lists: one-day items for another day are in [items] (the Catalogue) but not here.
  Iterable<StockItem> get onTodaysList => items.where((i) => i.onListOf(today.businessDate));
  Iterable<StockItem> get tracked => onTodaysList.where((i) => i.counted);
  Iterable<StockItem> get noCount => onTodaysList.where((i) => !i.counted);
  Iterable<StockItem> get live => onTodaysList.where((i) => i.live);

  StockItem? byVariant(String id) {
    for (final item in items) {
      if (item.variantId == id) return item;
    }
    return null;
  }

  String get currency => items.isEmpty ? 'INR' : items.first.currency;
}

/// Wording that depends on the kind of shop. Food shops answer allergy questions from `allergens`,
/// the one field here the assistant reads.
class ShopTerms {
  const ShopTerms._({
    required this.stockQuestion,
    required this.attrLabel,
    required this.attrKey,
    required this.attrOptions,
    required this.attrNote,
    required this.aliasExample,
    required this.exampleProduct,
  });

  final String stockQuestion;
  final String attrLabel;
  final String attrKey;
  final List<String> attrOptions;
  final String attrNote;
  final String aliasExample;
  final String exampleProduct;

  static final _food = RegExp(
    r'food|bak|cake|sweet|snack|cook|kitchen|cafe|tiffin|pickle|choco',
    caseSensitive: false,
  );

  factory ShopTerms.of(String? category, [Map<String, dynamic> attributes = const {}]) {
    if (attributes.containsKey('allergens') || (category != null && _food.hasMatch(category))) {
      return const ShopTerms._(
        stockQuestion: 'What did you make today?',
        attrLabel: 'Allergens',
        attrKey: 'allergens',
        attrOptions: ['Egg', 'Milk', 'Gluten', 'Nuts', 'Soy'],
        attrNote: 'I use this to answer allergy questions. If it is not here, I ask you.',
        aliasExample: 'lava cake, molten cake',
        exampleProduct: 'Choco lava',
      );
    }
    return const ShopTerms._(
      stockQuestion: 'What’s in stock today?',
      attrLabel: 'Details',
      attrKey: 'details',
      attrOptions: ['Size', 'Colour', 'Material', 'Care', 'Warranty'],
      // BACKEND GAP: get_product_details reads only ingredients, allergens and dietary from
      // attributes, so the assistant can't answer from `details` yet.
      attrNote: 'Saved with the product. sellix can’t answer from these yet, so it asks you.',
      aliasExample: 'A short name customers use',
      exampleProduct: 'Your product name',
    );
  }

  List<String> read(Map<String, dynamic> attributes) => switch (attributes[attrKey]) {
    final List<dynamic> list => [for (final v in list) '$v'],
    final String text when text.trim().isNotEmpty => text.split(',').map((s) => s.trim()).toList(),
    _ => const [],
  };
}

/// Finds "10 blue kurti" in free text, against the shop's own names and aliases.
Map<String, int> matchStockText(String text, Iterable<StockItem> items) {
  var rest = ' ${text.toLowerCase()} ';
  final names = <(String, String)>[
    for (final item in items) ...[
      (item.label.toLowerCase(), item.variantId),
      if (item.variant != null) ('${item.name} ${item.variant}'.toLowerCase(), item.variantId),
      (item.name.toLowerCase(), item.variantId),
      for (final alias in item.aliases) (alias.aliasText.toLowerCase(), item.variantId),
    ],
  ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  final found = <String, int>{};
  for (final (name, id) in names) {
    if (found.containsKey(id)) continue;
    final match = RegExp('(\\d+)\\s*(?:x\\s*)?${RegExp.escape(name)}').firstMatch(rest);
    if (match == null) continue;
    final count = int.parse(match[1]!);
    found[id] = count > stepperMax ? stepperMax : count;
    rest = rest.replaceFirst(match[0]!, ' ');
  }
  return found;
}
