import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../stock/stock_model.dart' show ShelfChoice, shelfLabel, startChoiceFor;
import '../stock/stock_providers.dart';
import '../stock/stock_widgets.dart' show StockTypeQuestion;
import 'ob_common.dart';

/// Stock already set today, so coming back keeps it. A new shop has none.
final _obTodayProvider = FutureProvider.autoDispose<Today>((ref) => ref.watch(sellixApiProvider).today());

/// One row on the list. Same product and variant is the same row.
///
/// [stockMode] and [shelfLifeDays] are what to send. Null means "leave the product as it is", which
/// is what a row loaded from the server must send until the owner changes it: sending the row's own
/// mode back (or a default) would silently rewrite the product. [knownMode] and [knownShelfDays] are
/// what the server has, only for showing.
class _Line {
  _Line({
    required this.product,
    this.variant,
    required this.priceMinor,
    required this.currency,
    required this.quantity,
    this.stockMode,
    this.shelfLifeDays,
    this.knownMode,
    this.knownShelfDays,
  });

  factory _Line.fromRow(StockRow r) => _Line(
    product: r.product,
    variant: r.variant,
    priceMinor: r.priceMinor,
    currency: r.currency,
    quantity: r.opening,
    knownMode: r.stockMode,
    knownShelfDays: r.shelfLifeDays,
  );

  /// A typed line. [old] is the row it replaces: it keeps that row's stock type, untouched.
  factory _Line.fromStock(StockLine l, {_Line? old, ShelfChoice? start}) => _Line(
    product: l.product,
    variant: l.variant,
    priceMinor: l.priceMinor,
    currency: l.currency,
    quantity: start?.isNoCount ?? false ? 0 : l.quantity,
    stockMode: old != null ? old.stockMode : start?.stockMode,
    shelfLifeDays: old != null ? old.shelfLifeDays : start?.shelfLifeDays,
    knownMode: old?.knownMode,
    knownShelfDays: old?.knownShelfDays,
  );

  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;
  final String? stockMode;
  final int? shelfLifeDays;
  final String? knownMode;
  final int? knownShelfDays;
  int quantity;

  String get label => variant == null || variant!.isEmpty ? product : '$product, $variant';

  /// The stock type it has or will get, if known.
  String? get mode => stockMode ?? knownMode;

  /// Made to order and always available have no count to set.
  bool get noCount => mode == StockMode.madeToOrder || mode == StockMode.unlimited;

  /// Made to order may be left without a price: the owner quotes each order.
  bool get needsPrice => mode != StockMode.madeToOrder;

  /// Goes live with this step: it has a count, or it needs none.
  bool get counts => quantity > 0 || noCount;

  bool sameName(String otherProduct, String? otherVariant) =>
      product.toLowerCase() == otherProduct.toLowerCase() &&
      (variant ?? '').toLowerCase() == (otherVariant ?? '').toLowerCase();

  bool same(_Line o) => sameName(o.product, o.variant);

  StockLine toStock() => StockLine(
    product: product,
    variant: variant,
    priceMinor: priceMinor,
    currency: currency,
    quantity: noCount ? 0 : quantity,
    stockMode: stockMode,
    shelfLifeDays: shelfLifeDays,
  );
}

class ObStockScreen extends ConsumerStatefulWidget {
  const ObStockScreen({super.key});

  @override
  ConsumerState<ObStockScreen> createState() => _ObStockScreenState();
}

class _ObStockScreenState extends ConsumerState<ObStockScreen> {
  List<_Line>? _lines;
  bool _saving = false;

  void _merge(Iterable<_Line> incoming) {
    final lines = [...?_lines];
    for (final line in incoming) {
      final at = lines.indexWhere(line.same);
      if (at >= 0) {
        lines[at] = line;
      } else {
        lines.add(line);
      }
    }
    setState(() => _lines = lines);
  }

  /// The shop type's questions and wording. The screen waits for it, so this is the real one.
  ProductSchema get _schema => ref.read(shopSchemaProvider);

  /// A typed line for a product that is neither on this list nor in the catalogue is a new product,
  /// so it starts as the shop type's usual way of stocking (the backend's own default is daily).
  /// A line for one that is already there leaves its stock type alone.
  _Line _typed(StockLine line, Set<String> catalogue, ShelfChoice start) {
    final old = (_lines ?? const <_Line>[]).where((l) => l.sameName(line.product, line.variant)).firstOrNull;
    final known = old != null || catalogue.contains(_key(line.product, line.variant));
    return _Line.fromStock(line, old: old, start: known ? null : start);
  }

  static String _key(String product, String? variant) => '${product.toLowerCase()}|${(variant ?? '').toLowerCase()}';

  Future<Set<String>> _catalogueKeys() async {
    try {
      final all = await ref.read(catalogProvider.future);
      return {
        for (final p in all)
          for (final v in p.variants) _key(p.name, v.name),
      };
    } on Object catch (_) {
      return {};
    }
  }

  Future<void> _typeIt() async {
    final parsed = await showSxSheet<List<StockLine>>(
      context,
      title: 'Type today’s stock',
      subtitle: 'Write the count, the name and the price. One line for each, or separate them with commas.',
      builder: (_) => _TypeSheet(example: _schema.vocabulary.exampleProduct),
    );
    if (parsed == null || !mounted) return;
    final catalogue = await _catalogueKeys();
    final start = startChoiceFor(_schema);
    final lines = [for (final l in parsed) _typed(l, catalogue, start)];
    if (mounted) _merge(lines);
  }

  Future<void> _addOne({_Line? editing}) async {
    final line = await showSxSheet<_Line>(
      context,
      title: editing == null ? 'Add your products' : 'Edit product',
      subtitle: editing == null ? 'A name, a price and how you stock it.' : null,
      builder: (_) => _ProductSheet(editing: editing, schema: _schema),
    );
    if (line == null || !mounted) return;
    if (editing != null && !editing.same(line)) {
      _lines = [...?_lines]..removeWhere(editing.same);
    }
    _merge([line]);
  }

  Future<void> _confirm() async {
    final lines = _lines ?? const <_Line>[];
    if (!lines.any((l) => l.counts)) {
      HapticFeedback.heavyImpact();
      showSxSnack(context, 'No counts yet. Add a product and set how many you have today.', icon: TablerIcons.package);
      return;
    }
    final unpriced = lines.where((l) => l.counts && l.needsPrice && l.priceMinor <= 0).firstOrNull;
    if (unpriced != null) {
      HapticFeedback.heavyImpact();
      showSxSnack(context, 'Add a price for ${unpriced.label} first.');
      _addOne(editing: unpriced);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).setOpeningStock([for (final l in lines) l.toStock()]);
      if (mounted) context.go(Routes.obLive);
    } catch (error) {
      if (mounted) showSxSnack(context, sxErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(_obTodayProvider);
    // The questions come from the shop type's schema, so the screen waits for it (it never fails:
    // the app has its own to fall back on).
    final schemaReady = ref.watch(productSchemaProvider).hasValue;
    final schema = ref.watch(shopSchemaProvider);
    if (_lines == null && today.hasValue) {
      _lines = [for (final row in today.requireValue.stock) _Line.fromRow(row)];
    }
    final lines = _lines;
    final empty = lines != null && lines.isEmpty;
    return SxScaffold(
      floating: lines == null || !schemaReady
          ? null
          : SxBottomCta(
              label: empty ? 'Add product' : 'Confirm and go live',
              icon: empty ? TablerIcons.plus : null,
              loading: _saving,
              onTap: empty ? _addOne : _confirm,
            ),
      body: Column(
        children: [
          ObTop(
            step: 3,
            fraction: 0.5,
            fallback: Routes.obTest,
            onSkip: () => context.go(Routes.obLive),
          ),
          Expanded(
            child: SxAsyncView<Today>(
              value: schemaReady ? today : const AsyncLoading<Today>(),
              onRetry: () => ref.invalidate(_obTodayProvider),
              loading: const SxSkeletonList(topHeight: 160),
              builder: (context, _) => SxScrollList(
                padding: EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s20, SxSpace.screen, sxBottomInset(context) + SxSpace.s20),
                children: [
                  ..._intro(context, schema.vocabulary),
                  if (empty)
                    const SxEmptyState(
                      icon: TablerIcons.package,
                      title: 'Add your first product',
                      body: 'A name, a price and how you stock it. You need one product to go live.',
                    )
                  else ...[
                    ..._rows(context, lines ?? const []),
                    const SizedBox(height: SxSpace.s4),
                    SxRowCard(
                      title: 'Add your products',
                      meta: 'A name, a price and how you stock it.',
                      icon: TablerIcons.plus,
                      outlined: true,
                      chevron: false,
                      onTap: _addOne,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _intro(BuildContext context, Vocabulary vocabulary) {
    final p = context.sx;
    return [
      SxFadeUp(child: Text(vocabulary.stockQuestion, style: SxText.titleL.copyWith(color: p.textPrimary))),
      const SizedBox(height: SxSpace.s8),
      SxFadeUp(
        index: 1,
        child: Text(
          'Type it and sellix makes the list. You fix the counts.',
          style: SxText.caption.copyWith(color: p.textSecondary),
        ),
      ),
      const SizedBox(height: SxSpace.s16),
      // BACKEND GAP: no endpoint for voice transcription or reading a photo of stock.
      const SxFadeUp(
        index: 2,
        child: SxVoiceCard(
          stateLabel: 'Speaking your stock is not available yet',
          stateIcon: TablerIcons.microphone_off,
          placeholder: 'For now, type it or add products one by one.',
          micLabel: 'Speaking is not available yet',
          onMic: null,
        ),
      ),
      const SizedBox(height: SxSpace.s12),
      SxFadeUp(
        index: 3,
        child: Wrap(
          spacing: SxSpace.s8,
          runSpacing: SxSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SxFilterChip(
              label: 'Type it',
              icon: TablerIcons.keyboard,
              selected: false,
              onTap: _typeIt,
            ),
            const SxFilterChip(label: 'Photo', icon: TablerIcons.camera, selected: false, onTap: null),
            Text('Photo is not available yet.', style: SxText.caption.copyWith(color: p.textSecondary)),
          ],
        ),
      ),
    ];
  }

  List<Widget> _rows(BuildContext context, List<_Line> lines) {
    return [
      SxSectionHeader(title: 'Your list: ${lines.length} ${lines.length == 1 ? 'item' : 'items'}'),
      for (final line in lines) ...[
        if (line.noCount)
          // No count to set: made to order, or always available.
          SxRowCard(
            title: line.label,
            meta: [
              shelfLabel(line.mode!, null),
              if (line.priceMinor > 0) money(line.priceMinor, line.currency) else if (line.needsPrice) 'Add a price' else 'Quote per order',
            ].join(' · '),
            leading: const SxIconTile(icon: TablerIcons.package),
            chevron: false,
            onTap: () => _addOne(editing: line),
          )
        else
          SxStockRow(
            leading: const SxIconTile(icon: TablerIcons.package),
            title: line.label,
            price: line.priceMinor > 0 ? money(line.priceMinor, line.currency) : null,
            chip: line.priceMinor <= 0
                ? const SxChip(label: 'Add a price', tone: SxChipTone.attention)
                : line.quantity == 0
                ? const SxChip(label: 'Not today')
                : null,
            value: line.quantity,
            max: 100000,
            onTap: () => _addOne(editing: line),
            onChanged: (v) => setState(() => line.quantity = v),
          ),
        const SizedBox(height: SxSpace.s8),
      ],
    ];
  }
}

class _TypeSheet extends ConsumerStatefulWidget {
  const _TypeSheet({required this.example});

  final String example;

  @override
  ConsumerState<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends ConsumerState<_TypeSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final hint =
        'No products found in that. Write a count, a name and a price, like “5 ${widget.example.toLowerCase()} 120”.';
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = hint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lines = await ref.read(sellixApiProvider).parseStockText(text);
      if (mounted) Navigator.of(context).pop(lines);
    } on ApiException catch (error) {
      // A 422 says which line it could not read.
      if (mounted) setState(() => _error = error.statusCode == 422 ? hint : error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SxField(
          controller: _text,
          hint: '5 ${widget.example.toLowerCase()} 120',
          maxLines: 4,
          autofocus: true,
          errorText: _error,
        ),
        const SizedBox(height: SxSpace.s16),
        SxButton(label: 'Make the list', icon: TablerIcons.sparkles, fullWidth: true, loading: _busy, onTap: _make),
      ],
    );
  }
}

/// The router keeps a shop that has not finished onboarding on `ob-*`, so the full add-product
/// screen can't open from here; this adds what opening stock needs. It asks the same stock question
/// as the add-product form, from the same schema.
class _ProductSheet extends StatefulWidget {
  const _ProductSheet({required this.schema, this.editing});

  final ProductSchema schema;
  final _Line? editing;

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final _name = TextEditingController(text: widget.editing?.product);
  late final _variant = TextEditingController(text: widget.editing?.variant);
  late final _price = TextEditingController(
    text: (widget.editing?.priceMinor ?? 0) > 0 ? minorToInput(widget.editing!.priceMinor) : '',
  );
  late int _count = widget.editing?.quantity ?? 1;

  /// What the product has now (a row from the server, or an earlier choice), else the shop type's start.
  late final ShelfChoice _first = _startingChoice();
  late ShelfChoice _choice = _first;
  String? _nameError;
  String? _priceError;
  String? _stockError;

  ShelfChoice _startingChoice() {
    final line = widget.editing;
    final mode = line?.mode;
    if (line == null || mode == null) return startChoiceFor(widget.schema);
    return ShelfChoice.of(mode, line.stockMode != null ? line.shelfLifeDays : line.knownShelfDays);
  }

  @override
  void dispose() {
    _name.dispose();
    _variant.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final priceText = _price.text.trim();
    final price = parseMoneyMinor(priceText);
    final priceless = _choice.c == 'mto' && priceText.isEmpty;
    setState(() {
      _nameError = name.isEmpty ? 'Enter the product’s name.' : null;
      _priceError = !priceless && (price == null || price <= 0) ? 'Enter a price, like 450 or 99.50.' : null;
      _stockError = _choice.isValid ? null : 'Enter 1 to 3650 days.';
    });
    if (_nameError != null || _priceError != null || _stockError != null) return;
    final line = widget.editing;
    // A product that already exists keeps its stock type unless the owner changed it here. A new
    // name is a new product, so it gets the choice shown.
    final keeps = line != null && line.sameName(name, obText(_variant.text)) && _choice.sameAs(_first);
    Navigator.of(context).pop(
      _Line(
        product: name,
        variant: obText(_variant.text),
        priceMinor: price ?? 0,
        currency: line?.currency ?? 'INR',
        quantity: _choice.isNoCount ? 0 : _count,
        stockMode: keeps ? line.stockMode : _choice.stockMode,
        shelfLifeDays: keeps ? line.shelfLifeDays : _choice.shelfLifeDays,
        knownMode: line?.knownMode,
        knownShelfDays: line?.knownShelfDays,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final currency = widget.editing?.currency ?? 'INR';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        SxField(controller: _name, label: 'Name', hint: 'Product name', maxLength: 200, errorText: _nameError, textCapitalization: TextCapitalization.sentences),
        SxField(controller: _variant, label: 'Size or type (optional)', hint: 'Small', maxLength: 200),
        SxField(
          controller: _price,
          label: _choice.c == 'mto' ? 'Price (optional)' : 'Price',
          prefix: currency == 'INR' ? '₹' : currency,
          hint: _choice.c == 'mto' ? 'Empty: you quote per order' : '450',
          errorText: _priceError,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (StockTypeQuestion.isNeeded(widget.schema, _choice, keepMode: widget.editing?.mode))
          StockTypeQuestion(
            schema: widget.schema,
            value: _choice,
            keepMode: widget.editing?.mode,
            errorText: _stockError,
            onChanged: (v) => setState(() {
              _choice = v;
              _stockError = null;
              if (v.c == 'mto') _priceError = null;
            }),
          ),
        if (!_choice.isNoCount)
          Row(
            children: [
              Expanded(child: Text('How many today?', style: SxText.bodyStrong.copyWith(color: p.textPrimary))),
              SxStepper(value: _count, max: 100000, itemName: 'this product', onChanged: (v) => setState(() => _count = v)),
            ],
          ),
        SxButton(label: 'Add to the list', icon: TablerIcons.check, fullWidth: true, onTap: _save),
      ],
    );
  }
}
