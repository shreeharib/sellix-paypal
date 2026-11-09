import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/api/sellix_api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'stock_actions.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

/// New product, or edit with [variantId].
///
/// What the form asks (how the shop stocks it, how long it keeps, which details) comes from the
/// shop type's product schema, so a dress shop is never asked how long a dress keeps.
///
/// BACKEND GAP: no create endpoint. `PUT /v1/today/stock` creates the product as a side effect, so a
/// new product always gets today's stock line, at zero when the merchant has none yet.
class AddProductScreen extends ConsumerWidget {
  const AddProductScreen({super.key, this.variantId});

  final String? variantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schema = ref.watch(productSchemaProvider);
    final view = ref.watch(stockViewProvider);
    return SxScaffold(
      body: SxAsyncView<StockView>(
        // The form starts from the schema, so it waits for it. The schema never fails: it falls back.
        value: schema.hasValue ? view : const AsyncLoading<StockView>(),
        onRetry: () {
          ref.invalidate(todayProvider);
          ref.invalidate(catalogProvider);
        },
        loading: const SxSkeletonList(topHeight: 160),
        isEmpty: (v) => variantId != null && v.byVariant(variantId!)?.productId == null,
        empty: const SxEmptyState(
          icon: TablerIcons.package_off,
          title: 'This product isn’t in your catalogue',
        ),
        builder: (context, view) => _Form(
          key: ValueKey(variantId),
          view: view,
          item: variantId == null ? null : view.byVariant(variantId!),
          schema: schema.requireValue,
        ),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({super.key, required this.view, required this.item, required this.schema});

  final StockView view;
  final StockItem? item;
  final ProductSchema schema;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  StockItem? get _item => widget.item;

  ProductSchema get _schema => widget.schema;

  late final _name = TextEditingController(text: _item?.name ?? '');
  late final _variant = TextEditingController(text: _item?.variant ?? '');
  late final _price = TextEditingController(
    text: (_item?.priceMinor ?? 0) > 0 ? minorToInput(_item!.priceMinor) : '',
  );
  late final _aliases = TextEditingController(text: _item?.aliases.map((a) => a.aliasText).join(', ') ?? '');
  late ShelfChoice _shelf = _item != null
      ? ShelfChoice.of(_item!.stockMode, _item!.shelfLifeDays)
      : _startChoice;

  // Detail fields, by the field's key. Each is made on first use from the product's own attributes.
  final _picked = <String, List<String>>{};
  final _own = <String, List<String>>{};
  final _texts = <String, TextEditingController>{};

  late final String _snapshot = _snap();
  int _count = 0;
  String? _nameError;
  String? _priceError;
  String? _shelfError;
  bool _saving = false;
  bool _done = false;
  int _nameShakes = 0;
  int _priceShakes = 0;

  /// The shelf life most of this shop's fresh-batch products use, if it has any.
  ShelfChoice? get _usualDaily {
    final tally = <String, int>{};
    final byKey = <String, ShelfChoice>{};
    for (final item in widget.view.tracked) {
      if (item.stockMode != StockMode.daily) continue;
      final choice = ShelfChoice.of(item.stockMode, item.shelfLifeDays);
      final key = '${choice.c}|${choice.days}';
      tally[key] = (tally[key] ?? 0) + 1;
      byKey[key] = choice;
    }
    if (tally.isEmpty) return null;
    return byKey[tally.entries.reduce((a, b) => b.value > a.value ? b : a).key];
  }

  /// A new product starts as the shop type's default mode.
  ShelfChoice get _startChoice => startChoiceFor(_schema, _usualDaily);

  // Details ---------------------------------------------------------------------------------

  Map<String, dynamic> get _attributes => _item?.attributes ?? const {};

  /// What is chosen for a chip field, in the order picked.
  List<String> _chosen(DetailField f) => _picked.putIfAbsent(f.key, () => [...f.values(_attributes)]);

  /// The product's own values that the schema doesn't list, and any the owner adds, as chips.
  List<String> _extras(DetailField f) => _own.putIfAbsent(f.key, () => [...f.values(_attributes)]);

  TextEditingController _line(DetailField f) => _texts.putIfAbsent(f.key, () {
    final controller = TextEditingController(text: f.text(_attributes));
    controller.addListener(_changed);
    return controller;
  });

  /// The value to save for a field, cleaned: a list for chips, a string for a text line.
  Object _valueOf(DetailField f) => f.isChoice ? [..._chosen(f)] : _clean(_line(f).text);

  Object _originalOf(DetailField f) => f.isChoice ? f.values(_attributes) : f.text(_attributes);

  bool _sameValue(DetailField f) {
    final now = _valueOf(f);
    final was = _originalOf(f);
    if (now is List<String> && was is List<String>) {
      return now.length == was.length && now.toSet().containsAll(was);
    }
    return now == was;
  }

  bool _isEmpty(Object value) => value is List ? value.isEmpty : '$value'.isEmpty;

  /// Only what changed, for the PATCH. The backend merges attributes key by key.
  Map<String, dynamic> get _changedDetails => {
    for (final f in _schema.detailFields)
      if (!_sameValue(f)) f.key: _valueOf(f),
  };

  /// Everything filled in, for a new product.
  Map<String, dynamic> get _filledDetails => {
    for (final f in _schema.detailFields)
      if (!_isEmpty(_valueOf(f))) f.key: _valueOf(f),
  };

  String _snap() =>
      '${_name.text}|${_variant.text}|${_price.text}|${_aliases.text}|${_shelf.c}|${_shelf.days}|$_count|'
      '${[for (final f in _schema.detailFields) f.isChoice ? (_chosen(f).toList()..sort()).join(',') : _line(f).text].join('|')}';

  bool get _dirty => _snap() != _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot;
    for (final c in [_name, _variant, _price, _aliases]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _variant.dispose();
    _price.dispose();
    _aliases.dispose();
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[<>"]'), '').trim();

  void _leave() => context.canPop() ? context.pop() : context.go(Routes.stock);

  Future<void> _close() async {
    if (!_dirty || _done) return _leave();
    final leave = await showSxConfirm(
      context,
      title: 'Leave without saving?',
      body: 'Your changes to this product will be lost.',
      confirmLabel: 'Leave',
      cancelLabel: 'Keep editing',
    );
    if (leave && mounted) _leave();
  }

  bool _validate() {
    final name = _clean(_name.text);
    final variant = _clean(_variant.text);
    final priceText = _price.text.trim();
    final price = parseMoneyMinor(priceText);
    String? nameError;
    String? priceError;
    String? shelfError;
    if (name.isEmpty) {
      nameError = 'Name is empty. Add the name customers know it by.';
    } else if (widget.view.items.any(
      (x) =>
          x.variantId != _item?.variantId &&
          x.name.toLowerCase() == name.toLowerCase() &&
          (x.variant ?? '').toLowerCase() == variant.toLowerCase(),
    )) {
      nameError = 'You already have $name${variant.isEmpty ? '' : ', $variant'}. Change the name or the variant.';
    }
    if (priceText.isNotEmpty && price == null) {
      priceError = 'Write the price as a number, like 500 or 89.50.';
    } else if (_shelf.c != 'mto' && (price ?? 0) == 0) {
      priceError = priceText.isEmpty
          ? 'Price is empty. Add a price, because sellix never guesses prices.'
          : 'Price can’t be zero. Add the selling price.';
    }
    if (!_shelf.isValid) {
      shelfError = 'Enter 1 to 3650 days.';
    } else if (_item != null) {
      shelfError = StockActions.shelfRefusal(_item!, _shelf);
    }
    setState(() {
      _nameError = nameError;
      _priceError = priceError;
      _shelfError = shelfError;
      if (nameError != null) _nameShakes++;
      if (priceError != null) _priceShakes++;
    });
    return nameError == null && priceError == null && shelfError == null;
  }

  List<String> get _aliasList => _aliases.text.split(',').map(_clean).where((s) => s.isNotEmpty).toList();

  Future<void> _save() async {
    if (_saving || _done) return;
    if (!_validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    final actions = StockActions(context);
    final api = ref.read(sellixApiProvider);
    try {
      final (message, offer) = _item != null ? await _saveEdit(api) : await _saveNew(api);
      actions.refresh();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _saving = false;
        _done = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      _leave();
      if (offer != null) {
        actions.offerAddStock(offer, message);
      } else {
        actions.announce(message, icon: TablerIcons.check);
      }
    } on Object catch (error) {
      // Whatever went wrong, the product may already exist: the lists look again.
      actions.refresh();
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _saving = false);
      showSxSnack(context, sxErrorMessage(error), icon: TablerIcons.alert_circle);
    }
  }

  Future<(String, StockItem?)> _saveEdit(SellixApi api) async {
    final item = _item!;
    final name = _clean(_name.text);
    final price = parseMoneyMinor(_price.text.trim()) ?? 0;
    final details = _changedDetails;
    final renamed = name != item.name;
    if (renamed || details.isNotEmpty) {
      await api.updateProduct(
        item.productId!,
        ProductUpdate(name: renamed ? name : null, attributes: details.isEmpty ? null : details),
      );
    }
    final was = ShelfChoice.of(item.stockMode, item.shelfLifeDays);
    final shelfChanged = !_shelf.sameAs(was);
    if (shelfChanged || price != item.priceMinor) {
      // The price and stock type live on the variant, and only the stock line can change them.
      await api.setOpeningStock([
        item.line(
          StockActions.shelfOpening(item, _shelf),
          shelf: shelfChanged ? _shelf : null,
          productName: name,
          price: price,
        ),
      ]);
    }
    final wanted = _aliasList;
    final lower = wanted.map((a) => a.toLowerCase()).toSet();
    final existing = item.aliases.map((a) => a.aliasText.toLowerCase()).toSet();
    for (final alias in item.aliases) {
      if (!lower.contains(alias.aliasText.toLowerCase())) {
        await api.deleteProductAlias(item.productId!, alias.id);
      }
    }
    for (final alias in wanted) {
      if (!existing.contains(alias.toLowerCase())) await api.addProductAlias(item.productId!, alias);
    }
    return !item.counted && !_shelf.isNoCount
        ? ('$name saved. Set a count so sellix can sell it.', item)
        : ('$name saved.', null);
  }

  Future<(String, StockItem?)> _saveNew(SellixApi api) async {
    final name = _clean(_name.text);
    final variant = _clean(_variant.text);
    final count = _shelf.isNoCount ? 0 : _count;
    final today = await api.setOpeningStock([
      StockLine(
        product: name,
        variant: variant.isEmpty ? null : variant,
        priceMinor: parseMoneyMinor(_price.text.trim()) ?? 0,
        currency: widget.view.currency,
        quantity: count,
        // The chosen mode, and a shelf life only for fresh batches.
        stockMode: _shelf.stockMode,
        shelfLifeDays: _shelf.shelfLifeDays,
      ),
    ]);
    final message = _shelf.isNoCount
        ? '$name added. sellix can sell it now.'
        : count > 0
        ? '$name added. ${units(count)} on sale today.'
        : '$name added. Set a count to put it on sale.';
    // A new product at zero: the snackbar's Add stock restocks the line just made.
    StockItem? offer;
    if (!_shelf.isNoCount && count == 0) {
      for (final item in StockView.join(today, const []).items) {
        if (item.name.toLowerCase() == name.toLowerCase() &&
            (item.variant ?? '').toLowerCase() == variant.toLowerCase()) {
          offer = item;
        }
      }
    }
    final details = _filledDetails;
    if (details.isEmpty && _aliasList.isEmpty) return (message, offer);
    // The stock line returns no product id, so the details wait for a lookup by name.
    final lost = ('$name added, but its details didn’t save. Add them with Edit product.', offer);
    try {
      final all = await api.products();
      final product = all.where((p) => p.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (product == null) return lost;
      if (details.isNotEmpty) await api.updateProduct(product.id, ProductUpdate(attributes: details));
      for (final alias in _aliasList) {
        await api.addProductAlias(product.id, alias);
      }
    } on Exception {
      return lost;
    }
    return (message, offer);
  }

  Future<void> _addOption(DetailField f) async {
    final text = await showSxSheet<String>(
      context,
      title: 'Add your own',
      subtitle: 'Something customers ask about: ${f.label.toLowerCase()}.',
      builder: (_) => _DetailSheet(hint: f.options.firstOrNull ?? f.label),
    );
    if (text == null || !mounted) return;
    final known = [...f.options, ..._extras(f)];
    final match = known.where((a) => a.toLowerCase() == text.toLowerCase()).firstOrNull;
    setState(() {
      if (match == null) _extras(f).add(text);
      final value = match ?? text;
      if (!_chosen(f).contains(value)) _chosen(f).add(value);
    });
  }

  Widget _choiceField(DetailField f) {
    final p = context.sx;
    final options = {...f.options, ..._extras(f)}.toList();
    final chosen = _chosen(f);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: SxSpace.s8,
      children: [
        Text(f.label, style: SxText.label.copyWith(color: p.textPrimary)),
        Wrap(
          spacing: SxSpace.s8,
          runSpacing: SxSpace.s8,
          children: [
            for (final option in options)
              SxPickChip(
                label: option,
                selected: chosen.contains(option),
                onTap: () => setState(() => chosen.contains(option) ? chosen.remove(option) : chosen.add(option)),
              ),
            SxPickChip(label: 'Other', icon: TablerIcons.plus, selected: false, onTap: () => _addOption(f)),
          ],
        ),
        if (f.note.isNotEmpty) SxAiNote(f.note),
      ],
    );
  }

  Widget _textField(DetailField f) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SxSpace.s8,
    children: [
      SxField(label: f.label, controller: _line(f), maxLength: 200),
      if (f.note.isNotEmpty) SxAiNote(f.note),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final item = _item;
    final vocabulary = _schema.vocabulary;
    final currency = item?.currency ?? widget.view.currency;
    final symbol = currency == 'INR' ? '₹' : currency;
    return PopScope(
      canPop: !_dirty || _done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s8, SxSpace.screen, SxSpace.s8),
                child: Row(
                  children: [
                    SxIconButton(icon: TablerIcons.x, semanticLabel: 'Close', onTap: _close),
                    const SizedBox(width: SxSpace.s12),
                    Expanded(
                      child: Text(
                        item != null ? 'Edit product' : 'New product',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SxText.titleM.copyWith(color: p.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SxScrollList(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: SxSpace.s16,
                        children: [
                          // BACKEND GAP: base_image_url exists, but nothing uploads a photo to get one.
                          SxRowCard(
                            title: 'Add photo',
                            meta: 'Photos aren’t ready yet. sellix sells without them.',
                            icon: TablerIcons.camera_plus,
                            outlined: true,
                            chevron: false,
                          ),
                          SxShake(
                            trigger: _nameShakes,
                            child: SxField(
                              label: 'Name',
                              controller: _name,
                              hint: vocabulary.exampleProduct,
                              maxLength: 200,
                              errorText: _nameError,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) {
                                if (_nameError != null) setState(() => _nameError = null);
                              },
                            ),
                          ),
                          SxField(
                            label: 'Variant (optional)',
                            controller: _variant,
                            hint: 'Size, colour or weight',
                            maxLength: 100,
                            // BACKEND GAP: no endpoint renames a variant; a new name makes a new variant.
                            enabled: item == null,
                          ),
                          if (item != null)
                            Text(
                              'A variant’s name can’t be changed yet.',
                              style: SxText.caption.copyWith(color: p.textSecondary),
                            ),
                          SxShake(
                            trigger: _priceShakes,
                            child: SxField(
                              label: _shelf.c == 'mto' ? 'Price (optional)' : 'Price',
                              controller: _price,
                              prefix: symbol,
                              hint: _shelf.c == 'mto' ? 'Empty: you quote per order' : '500',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                              maxLength: 10,
                              errorText: _priceError,
                              onChanged: (_) {
                                if (_priceError != null) setState(() => _priceError = null);
                              },
                            ),
                          ),
                          if (StockTypeQuestion.isNeeded(_schema, _shelf, keepMode: item?.stockMode))
                            StockTypeQuestion(
                              schema: _schema,
                              value: _shelf,
                              keepMode: item?.stockMode,
                              dailyStart: _usualDaily,
                              errorText: _shelfError,
                              onChanged: (v) => setState(() {
                                _shelf = v;
                                _shelfError = null;
                                if (v.c == 'mto') _priceError = null;
                              }),
                            )
                          else if (_shelfError != null)
                            WhyText(_shelfError!),
                          if (item == null && !_shelf.isNoCount)
                            WhyStockRow(
                              title: 'How many do you have now?',
                              meta: 'Zero keeps it off today’s list.',
                              value: _count,
                              whyMin: 'Zero keeps it off today’s list.',
                              whyMax: 'The most you can set is $stepperMax.',
                              onChanged: (v) => setState(() => _count = v),
                            ),
                          if (_schema.detailFields.isNotEmpty)
                            Text('Details customers ask about', style: SxText.label.copyWith(color: p.textPrimary)),
                          for (final f in _schema.detailFields) f.isChoice ? _choiceField(f) : _textField(f),
                          SxField(
                            label: 'Other names customers use',
                            controller: _aliases,
                            hint: vocabulary.aliasExample,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: SxSpace.screen,
            right: SxSpace.screen,
            bottom: MediaQuery.paddingOf(context).bottom + SxSpace.navGap,
            child: SxBottomCta(
              label: _done ? 'Saved' : 'Save product',
              icon: TablerIcons.check,
              loading: _saving,
              done: _done,
              onTap: _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.hint});

  final String hint;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SxField(controller: _text, hint: widget.hint, maxLength: 40, autofocus: true, errorText: _error),
      const SizedBox(height: SxSpace.s16),
      SxButton(
        label: 'Add detail',
        fullWidth: true,
        onTap: () {
          final value = _text.text.replaceAll(RegExp(r'[<>"]'), '').trim();
          if (value.isEmpty) {
            setState(() => _error = 'Nothing typed. Write the detail, then add it.');
            return;
          }
          Navigator.of(context).pop(value);
        },
      ),
    ],
  );
}
