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
/// BACKEND GAP: no create endpoint. `PUT /v1/today/stock` creates the product as a side effect, so a
/// new product always gets today's stock line, at zero when the merchant has none yet.
class AddProductScreen extends ConsumerWidget {
  const AddProductScreen({super.key, this.variantId});

  final String? variantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SxScaffold(
      body: SxAsyncView<StockView>(
        value: ref.watch(stockViewProvider),
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
        ),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({super.key, required this.view, required this.item});

  final StockView view;
  final StockItem? item;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  StockItem? get _item => widget.item;

  late final _name = TextEditingController(text: _item?.name ?? '');
  late final _variant = TextEditingController(text: _item?.variant ?? '');
  late final _price = TextEditingController(
    text: (_item?.priceMinor ?? 0) > 0 ? minorToInput(_item!.priceMinor) : '',
  );
  late final _aliases = TextEditingController(text: _item?.aliases.map((a) => a.aliasText).join(', ') ?? '');
  late ShelfChoice _shelf = _item != null ? ShelfChoice.of(_item!.stockMode, _item!.shelfLifeDays) : _suggested;
  late final Set<String> _details = _startDetails.toSet();
  late final List<String> _extra = [..._startDetails];
  late final String _snapshot = _snap();
  int _count = 0;
  String? _nameError;
  String? _priceError;
  String? _shelfError;
  bool _saving = false;
  bool _done = false;
  int _nameShakes = 0;
  int _priceShakes = 0;

  ShopTerms get _terms =>
      ShopTerms.of(ref.read(shopAnswersProvider).value?.category, _item?.attributes ?? const {});

  List<String> get _startDetails => _item == null ? const [] : _terms.read(_item!.attributes);

  /// What this shop's products mostly use.
  ShelfChoice get _suggested {
    final tally = <String, int>{};
    final byKey = <String, ShelfChoice>{};
    for (final item in widget.view.tracked) {
      final choice = ShelfChoice.of(item.stockMode, item.shelfLifeDays);
      final key = '${choice.c}|${choice.days}';
      tally[key] = (tally[key] ?? 0) + 1;
      byKey[key] = choice;
    }
    if (tally.isEmpty) return const ShelfChoice('none');
    final top = tally.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return byKey[top]!;
  }

  String _snap() =>
      '${_name.text}|${_variant.text}|${_price.text}|${_aliases.text}|${_shelf.c}|${_shelf.days}|$_count|'
      '${(_details.toList()..sort()).join(',')}';

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
      shelfError = 'Enter 1 to 3650 days. If it never ends, choose Doesn’t expire.';
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
    } on Exception catch (error) {
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
    final before = _terms.read(item.attributes).toSet();
    final detailsChanged = before.length != _details.length || !before.containsAll(_details);
    final renamed = name != item.name;
    if (renamed || detailsChanged) {
      await api.updateProduct(
        item.productId!,
        ProductUpdate(
          name: renamed ? name : null,
          attributes: detailsChanged ? {_terms.attrKey: _details.toList()} : null,
        ),
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
    if (_details.isEmpty && _aliasList.isEmpty) return (message, offer);
    // The stock line returns no product id, so the details wait for a lookup by name.
    try {
      final all = await api.products();
      final product = all.firstWhere((p) => p.name.toLowerCase() == name.toLowerCase());
      if (_details.isNotEmpty) {
        await api.updateProduct(product.id, ProductUpdate(attributes: {_terms.attrKey: _details.toList()}));
      }
      for (final alias in _aliasList) {
        await api.addProductAlias(product.id, alias);
      }
    } on Exception {
      return ('$name added, but its details didn’t save. Add them with Edit product.', offer);
    }
    return (message, offer);
  }

  Future<void> _addDetail() async {
    final text = await showSxSheet<String>(
      context,
      title: 'Add a detail',
      subtitle: 'What do customers ask about? ${_terms.attrLabel}, size, care.',
      builder: (_) => _DetailSheet(hint: _terms.attrOptions.first),
    );
    if (text == null || !mounted) return;
    final known = [..._terms.attrOptions, ..._extra];
    final match = known.where((a) => a.toLowerCase() == text.toLowerCase()).firstOrNull;
    setState(() {
      if (match == null) _extra.add(text);
      _details.add(match ?? text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final item = _item;
    final terms = _terms;
    final options = {...terms.attrOptions, ..._extra}.toList();
    final currency = item?.currency ?? widget.view.currency;
    final symbol = currency == 'INR' ? '₹' : currency;
    final category = ref.watch(shopAnswersProvider).value?.category;
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
                              hint: terms.exampleProduct,
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
                          ShelfPicker(
                            value: _shelf,
                            errorText: _shelfError,
                            suggestion: item == null && widget.view.tracked.isNotEmpty && category != null
                                ? 'Suggested for ${category.toLowerCase()}'
                                : null,
                            onChanged: (v) => setState(() {
                              _shelf = v;
                              _shelfError = null;
                              if (v.c == 'mto') _priceError = null;
                            }),
                          ),
                          if (item == null && !_shelf.isNoCount)
                            WhyStockRow(
                              title: 'How many do you have now?',
                              meta: 'Zero keeps it off today’s list.',
                              value: _count,
                              whyMin: 'Zero keeps it off today’s list.',
                              whyMax: 'The most you can set is $stepperMax.',
                              onChanged: (v) => setState(() => _count = v),
                            ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: SxSpace.s8,
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: 'Details customers ask ',
                                  children: [
                                    TextSpan(
                                      text: '· ${terms.attrLabel}',
                                      style: TextStyle(color: p.textSecondary),
                                    ),
                                  ],
                                ),
                                style: SxText.label.copyWith(color: p.textPrimary),
                              ),
                              Wrap(
                                spacing: SxSpace.s8,
                                runSpacing: SxSpace.s8,
                                children: [
                                  for (final a in options)
                                    SxPickChip(
                                      label: a,
                                      selected: _details.contains(a),
                                      onTap: () => setState(
                                        () => _details.contains(a) ? _details.remove(a) : _details.add(a),
                                      ),
                                    ),
                                  SxPickChip(
                                    label: 'Other',
                                    icon: TablerIcons.plus,
                                    selected: false,
                                    onTap: _addDetail,
                                  ),
                                ],
                              ),
                              SxAiNote(terms.attrNote),
                            ],
                          ),
                          SxField(
                            label: 'Other names customers use',
                            controller: _aliases,
                            hint: terms.aliasExample,
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
