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
import 'ob_categories.dart';
import 'ob_common.dart';

/// Stock already set today, so coming back keeps it. A new shop has none.
final _obTodayProvider = FutureProvider.autoDispose<Today>((ref) => ref.watch(sellixApiProvider).today());

/// One row on the list. Same product and variant is the same row.
class _Line {
  _Line({
    required this.product,
    this.variant,
    required this.priceMinor,
    required this.currency,
    required this.quantity,
    this.stockMode,
    this.shelfLifeDays,
  });

  factory _Line.fromRow(StockRow r) => _Line(
    product: r.product,
    variant: r.variant,
    priceMinor: r.priceMinor,
    currency: r.currency,
    quantity: r.opening,
    stockMode: r.stockMode,
    shelfLifeDays: r.shelfLifeDays,
  );

  factory _Line.fromStock(StockLine l) => _Line(
    product: l.product,
    variant: l.variant,
    priceMinor: l.priceMinor,
    currency: l.currency,
    quantity: l.quantity,
    stockMode: l.stockMode,
    shelfLifeDays: l.shelfLifeDays,
  );

  final String product;
  final String? variant;
  final int priceMinor;
  final String currency;
  final String? stockMode;
  final int? shelfLifeDays;
  int quantity;

  String get label => variant == null || variant!.isEmpty ? product : '$product, $variant';

  bool same(_Line o) => product.toLowerCase() == o.product.toLowerCase() && (variant ?? '').toLowerCase() == (o.variant ?? '').toLowerCase();

  StockLine toStock() => StockLine(
    product: product,
    variant: variant,
    priceMinor: priceMinor,
    currency: currency,
    quantity: quantity,
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

  Future<void> _typeIt(ObCategory category) async {
    final parsed = await showSxSheet<List<StockLine>>(
      context,
      title: 'Type today’s stock',
      subtitle: 'Write the count, the name and the price. One line for each, or separate them with commas.',
      builder: (_) => _TypeSheet(example: category.exampleProduct),
    );
    if (parsed != null && mounted) _merge(parsed.map(_Line.fromStock));
  }

  Future<void> _addOne({_Line? editing}) async {
    final line = await showSxSheet<_Line>(
      context,
      title: editing == null ? 'Add your products' : 'Edit product',
      subtitle: editing == null ? 'A name, a price and how long you can sell it.' : null,
      builder: (_) => _ProductSheet(editing: editing),
    );
    if (line == null || !mounted) return;
    if (editing != null && !editing.same(line)) {
      _lines = [...?_lines]..removeWhere(editing.same);
    }
    _merge([line]);
  }

  Future<void> _confirm() async {
    final lines = _lines ?? const <_Line>[];
    if (!lines.any((l) => l.quantity > 0)) {
      HapticFeedback.heavyImpact();
      showSxSnack(context, 'No counts yet. Add a product and set how many you have today.', icon: TablerIcons.package);
      return;
    }
    final unpriced = lines.where((l) => l.quantity > 0 && l.priceMinor <= 0).firstOrNull;
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
    final draft = ref.watch(onboardingDraftProvider);
    if (_lines == null && today.hasValue) {
      _lines = [for (final row in today.requireValue.stock) _Line.fromRow(row)];
    }
    final category = obCategoryOf(draft.value?.answers.category) ?? obOtherCategory;
    final lines = _lines;
    final empty = lines != null && lines.isEmpty;
    return SxScaffold(
      floating: lines == null
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
              value: today,
              onRetry: () => ref.invalidate(_obTodayProvider),
              loading: const SxSkeletonList(topHeight: 160),
              builder: (context, _) => SxScrollList(
                padding: EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s20, SxSpace.screen, sxBottomInset(context) + SxSpace.s20),
                children: [
                  ..._intro(context, category),
                  if (empty)
                    const SxEmptyState(
                      icon: TablerIcons.package,
                      title: 'Add your first product',
                      body: 'A name, a price and how long you can sell it. You need one product to go live.',
                    )
                  else ...[
                    ..._rows(context, lines ?? const []),
                    const SizedBox(height: SxSpace.s4),
                    SxRowCard(
                      title: 'Add your products',
                      meta: 'A name, a price and how long you can sell it.',
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

  List<Widget> _intro(BuildContext context, ObCategory category) {
    final p = context.sx;
    return [
      SxFadeUp(child: Text(category.stockQuestion, style: SxText.titleL.copyWith(color: p.textPrimary))),
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
              onTap: () => _typeIt(category),
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
    final hint = 'No products found in that. Write a count, a name and a price, like “5 ${widget.example} 120”.';
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
          hint: '5 ${widget.example} 120',
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
/// screen can't open from here; this adds what opening stock needs.
class _ProductSheet extends StatefulWidget {
  const _ProductSheet({this.editing});

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
  /// Null keeps what the product has; a new product starts as today only.
  late String? _mode = widget.editing == null ? StockMode.daily : widget.editing!.stockMode;
  String? _nameError;
  String? _priceError;

  @override
  void dispose() {
    _name.dispose();
    _variant.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final price = parseMoneyMinor(_price.text);
    setState(() {
      _nameError = name.isEmpty ? 'Enter the product’s name.' : null;
      _priceError = price == null || price <= 0 ? 'Enter a price, like 450 or 99.50.' : null;
    });
    if (_nameError != null || _priceError != null) return;
    Navigator.of(context).pop(
      _Line(
        product: name,
        variant: obText(_variant.text),
        priceMinor: price!,
        currency: widget.editing?.currency ?? 'INR',
        quantity: _count,
        stockMode: _mode,
        shelfLifeDays: widget.editing?.shelfLifeDays,
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
          label: 'Price',
          prefix: currency == 'INR' ? '₹' : currency,
          hint: '450',
          errorText: _priceError,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        Row(
          children: [
            Expanded(child: Text('How many today?', style: SxText.bodyStrong.copyWith(color: p.textPrimary))),
            SxStepper(value: _count, max: 100000, itemName: 'this product', onChanged: (v) => setState(() => _count = v)),
          ],
        ),
        const ObLabel('How long can you sell it?'),
        SxSegmented<String>(
          segments: const [SxSegment(StockMode.daily, 'Today only'), SxSegment(StockMode.inventory, 'Until sold')],
          value: _mode == null || _mode == StockMode.daily ? StockMode.daily : StockMode.inventory,
          onChanged: (v) => setState(() => _mode = v),
        ),
        SxButton(label: 'Add to the list', icon: TablerIcons.check, fullWidth: true, onTap: _save),
      ],
    );
  }
}
