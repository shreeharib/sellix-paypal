import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

String _long(DateTime d) => DateFormat('EEE, d MMM').format(d);

/// Everything this screen needs: the shop's date, its products and the stock already set ahead.
class _DayData {
  const _DayData(this.today, this.catalog, this.upcoming);

  final Today today;
  final List<ProductDetail> catalog;
  final List<UpcomingDay> upcoming;
}

final _dayDataProvider = FutureProvider.autoDispose<_DayData>((ref) async {
  final results = await Future.wait<Object>([
    ref.watch(todayProvider.future),
    ref.watch(catalogProvider.future),
    ref.watch(upcomingProvider.future),
  ]);
  return _DayData(
    results[0] as Today,
    results[1] as List<ProductDetail>,
    results[2] as List<UpcomingDay>,
  );
});

/// One line of the list: a product, its price and the count for the day.
class _Entry {
  _Entry({
    required this.name,
    required this.variant,
    required this.priceMinor,
    required this.currency,
    required this.count,
    this.held = 0,
    this.isNew = false,
    this.oneDay,
    this.orderBy,
  });

  final String name;
  final String? variant;
  final int priceMinor;
  final String currency;
  int count;

  /// Held by orders already: the count can't go below it.
  final int held;

  /// Not in the catalogue yet.
  final bool isNew;

  /// Already a one-day item, from the day's stock.
  final DateTime? oneDay;
  final DateTime? orderBy;

  String get key => itemName(name, variant).toLowerCase();
  String get label => itemName(name, variant);
}

/// Stock for a later day, set the way today's list is: type it, add items, create a new product,
/// fix the counts. A new product here can be a one-day item (a festival special for 9 Nov) that stays
/// off every other day's list, today's included, with a last day to order.
class DayStockScreen extends ConsumerStatefulWidget {
  const DayStockScreen({super.key, this.day});

  /// The day to set. Left out: tomorrow.
  final DateTime? day;

  @override
  ConsumerState<DayStockScreen> createState() => _DayStockScreenState();
}

class _DayStockScreenState extends ConsumerState<DayStockScreen> {
  DateTime? _day;
  List<_Entry>? _entries;
  bool _oneDay = true;
  bool _touchedOneDay = false;
  DateTime? _lastOrder;
  int _range = 1;
  bool _saving = false;
  String? _error;

  DateTime _today(_DayData data) => dateOnly(data.today.businessDate);

  /// What the server already holds for [day].
  void _load(_DayData data, DateTime day) {
    final fixed = <_Entry>[];
    for (final d in data.upcoming) {
      if (daysBetween(d.date, day) != 0) continue;
      for (final item in d.items) {
        if (item.opening <= 0) continue;
        fixed.add(
          _Entry(
            name: item.product,
            variant: item.variant,
            priceMinor: item.priceMinor,
            currency: item.currency,
            count: item.opening,
            held: item.held,
            oneDay: item.availableOn,
            orderBy: item.orderByDate,
          ),
        );
      }
    }
    _entries = fixed;
    _lastOrder = fixed.map((e) => e.orderBy).whereType<DateTime>().firstOrNull;
    _oneDay = fixed.isEmpty || fixed.any((e) => e.oneDay != null);
    _touchedOneDay = false;
    _range = 1;
    _error = null;
  }

  /// Products the shop can already count, minus other days' one-day items.
  List<_Entry> _catalogue(_DayData data, DateTime day) => [
    for (final product in data.catalog)
      if (product.isActive &&
          isCounted(product.stockMode) &&
          (product.availableOn == null || daysBetween(product.availableOn!, day) == 0))
        for (final v in product.variants)
          if (v.isActive)
            _Entry(
              name: product.name,
              variant: v.name,
              priceMinor: v.priceMinor,
              currency: v.currency,
              count: 0,
            ),
  ];

  Future<void> _pickDay(_DayData data) async {
    final today = _today(data);
    final picked = await showDatePicker(
      context: context,
      initialDate: _day!,
      firstDate: addDays(today, 1),
      lastDate: addDays(today, 30),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = dateOnly(picked);
      _load(data, _day!);
    });
  }

  Future<void> _pickLastOrder(DateTime today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastOrder ?? today,
      firstDate: today,
      lastDate: _day!,
      helpText: 'Last day to order',
    );
    if (picked != null && mounted) setState(() => _lastOrder = dateOnly(picked));
  }

  void _add(_Entry entry) {
    final existing = _entries!.where((e) => e.key == entry.key).firstOrNull;
    HapticFeedback.lightImpact();
    setState(() {
      if (existing != null) {
        existing.count = entry.count > 0 ? entry.count : existing.count;
      } else {
        _entries!.add(entry);
        // A product made for this day is that day's item, unless the merchant says otherwise.
        if (entry.isNew && !_touchedOneDay) _oneDay = true;
      }
    });
  }

  Future<void> _addItem(_DayData data) async {
    final have = _entries!.map((e) => e.key).toSet();
    final choices = _catalogue(data, _day!).where((e) => !have.contains(e.key)).toList();
    final picked = await showSxSheet<Object>(
      context,
      title: 'Add an item',
      subtitle: 'For ${_long(_day!)}',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          for (final item in choices)
            SxChoiceCard(
              title: item.label,
              subtitle: money(item.priceMinor, item.currency),
              icon: TablerIcons.package,
              onTap: () => Navigator.of(sheet).pop(item),
            ),
          SxChoiceCard(
            title: 'New product',
            subtitle: 'A name, a price and how many',
            icon: TablerIcons.plus,
            onTap: () => Navigator.of(sheet).pop('+new'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked is _Entry) {
      _add(_Entry(
        name: picked.name,
        variant: picked.variant,
        priceMinor: picked.priceMinor,
        currency: picked.currency,
        count: 1,
      ));
      return;
    }
    final created = await showSxSheet<_Entry>(
      context,
      title: 'New product',
      subtitle: 'For ${_long(_day!)}',
      builder: (_) => _NewProductSheet(
        currency: data.catalog.firstOrNull?.variants.firstOrNull?.currency,
        example: ShopTerms.of(ref.read(shopAnswersProvider).value?.category).exampleProduct,
      ),
    );
    if (created != null && mounted) _add(created);
  }

  Future<void> _typeIt(_DayData data) async {
    final terms = ShopTerms.of(ref.read(shopAnswersProvider).value?.category);
    final lines = await showSxSheet<List<StockLine>>(
      context,
      title: 'Type the stock for ${_long(_day!)}',
      subtitle: 'One line is fine. Write the count, the name and the price.',
      builder: (_) => _TypeSheet(example: terms.exampleProduct),
    );
    if (lines == null || !mounted) return;
    final catalogue = {for (final e in _catalogue(data, _day!)) e.key: e};
    for (final line in lines) {
      final key = itemName(line.product, line.variant).toLowerCase();
      // The catalogue keeps its price: typing a count must not change one quietly.
      final known = catalogue[key];
      _add(_Entry(
        name: known?.name ?? line.product,
        variant: known?.variant ?? line.variant,
        priceMinor: known?.priceMinor ?? line.priceMinor,
        currency: known?.currency ?? line.currency,
        count: line.quantity > stepperMax ? stepperMax : line.quantity,
        isNew: known == null,
      ));
    }
  }

  Future<void> _save(_DayData data) async {
    final entries = _entries!;
    final lines = [
      for (final e in entries)
        if (e.count > 0 || e.held > 0 || !e.isNew)
          StockLine(
            product: e.name,
            variant: e.variant,
            priceMinor: e.priceMinor,
            currency: e.currency,
            quantity: e.count,
          ),
    ];
    if (entries.every((e) => e.count == 0)) {
      HapticFeedback.heavyImpact();
      setState(() => _error = 'All counts are zero. Set a count for at least one item.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final oneDay = _oneDay && _range == 1;
    try {
      await ref
          .read(sellixApiProvider)
          .setUpcomingStock(
            _day!,
            addDays(_day!, _range - 1),
            lines,
            oneDayOnly: oneDay,
            lastOrderDate: oneDay ? _lastOrder : null,
          );
    } on Exception catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _saving = false;
        _error = sxErrorMessage(error);
      });
      return;
    }
    ref
      ..invalidate(upcomingProvider)
      ..invalidate(catalogProvider)
      ..invalidate(todayProvider);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final label = _range == 1 ? _long(_day!) : '${_long(_day!)} to ${_long(addDays(_day!, _range - 1))}';
    if (context.canPop()) {
      context.pop('Stock set for $label.');
    } else {
      context.go(Routes.stock);
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.stock);

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(_dayDataProvider);
    final data = value.value;
    if (data != null && _entries == null) {
      final first = widget.day == null ? addDays(_today(data), 1) : dateOnly(widget.day!);
      _day = first.isAfter(_today(data)) ? first : addDays(_today(data), 1);
      _load(data, _day!);
    }
    return SxScaffold(
      floating: data == null || _entries == null
          ? null
          : SxBottomCta(
              label: _saving ? 'Saving…' : 'Save stock for ${DateFormat('d MMM').format(_day!)}',
              loading: _saving,
              onTap: _saving ? null : () => _save(data),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s8, SxSpace.screen, 0),
            child: Row(
              children: [
                SxIconButton(icon: TablerIcons.x, semanticLabel: 'Close', onTap: _close),
                const SizedBox(width: SxSpace.s12),
                if (data != null && _day != null)
                  SxChip(label: _long(_day!), icon: TablerIcons.calendar),
              ],
            ),
          ),
          Expanded(
            child: SxAsyncView<_DayData>(
              value: value,
              onRetry: () => ref.invalidate(_dayDataProvider),
              loading: const SxSkeletonList(topHeight: 160),
              builder: (context, data) => _entries == null ? const SizedBox.shrink() : _body(data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(_DayData data) {
    final p = context.sx;
    final today = _today(data);
    final entries = _entries!;
    final hasNew = entries.any((e) => e.isNew || e.oneDay != null);
    Widget side(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: child,
    );
    return SxScrollList(
      onRefresh: () async {
        ref.invalidate(_dayDataProvider);
        await ref.read(_dayDataProvider.future);
      },
      children: [
        const SizedBox(height: SxSpace.s20),
        side(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What will you have on ${_long(_day!)}?',
                style: SxText.titleL.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: SxSpace.s8),
              Text(
                'Customers can order ahead for this day. It stays off today’s list.',
                style: SxText.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s12),
        SxFilterChips(
          children: [
            SxFilterChip(
              label: 'Type it',
              icon: TablerIcons.keyboard,
              selected: false,
              onTap: () => _typeIt(data),
            ),
            SxFilterChip(
              label: 'Change day',
              icon: TablerIcons.calendar,
              selected: false,
              onTap: () => _pickDay(data),
            ),
          ],
        ),
        const SizedBox(height: SxSpace.s12),
        side(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.listGap,
            children: [
              for (final entry in entries)
                WhyStockRow(
                  key: ValueKey(entry.key),
                  title: entry.label,
                  meta: [
                    if (entry.isNew) 'New',
                    money(entry.priceMinor, entry.currency),
                    if (entry.held > 0) 'On hold ${entry.held}',
                  ].join(' · '),
                  value: entry.count,
                  min: entry.held,
                  whyMin: entry.held > 0
                      ? '${entry.held} on hold for this day. You can’t go below ${entry.held}.'
                      : 'Zero keeps it off this day.',
                  whyMax: 'The most you can set is $stepperMax.',
                  onChanged: (v) => setState(() => entry.count = v),
                ),
              SxRowCard(
                title: entries.isEmpty ? 'Add an item' : 'Add another item',
                icon: TablerIcons.plus,
                outlined: true,
                chevron: false,
                onTap: () => _addItem(data),
              ),
            ],
          ),
        ),
        if (hasNew || entries.isEmpty) ...[
          const SizedBox(height: SxSpace.s16),
          side(
            SxSwitchRow(
              title: 'Only on this day',
              subtitle: 'New items are sold on ${_long(_day!)} only, and never show on other days.',
              icon: TablerIcons.calendar_event,
              value: _oneDay,
              onChanged: (v) => setState(() {
                _oneDay = v;
                _touchedOneDay = true;
              }),
            ),
          ),
        ],
        if (_oneDay) ...[
          const SizedBox(height: SxSpace.s8),
          side(
            SxRowCard(
              title: 'Last day to order',
              meta: _lastOrder == null
                  ? 'Until the stock runs out'
                  : '${_long(_lastOrder!)}. Orders close after it.',
              icon: TablerIcons.clock_stop,
              onTap: () => _pickLastOrder(today),
              trailing: _lastOrder == null
                  ? null
                  : SxIconButton(
                      icon: TablerIcons.x,
                      semanticLabel: 'Clear last order day',
                      onTap: () => setState(() => _lastOrder = null),
                    ),
            ),
          ),
        ] else ...[
          const SizedBox(height: SxSpace.s16),
          side(Text('Same count for', style: SxText.label.copyWith(color: p.textPrimary))),
          const SizedBox(height: SxSpace.s8),
          side(
            Wrap(
              spacing: SxSpace.s8,
              runSpacing: SxSpace.s8,
              children: [
                for (final (n, label) in const [(1, 'This day'), (3, 'Next 3 days'), (7, 'Next 7 days')])
                  SxPickChip(label: label, selected: _range == n, onTap: () => setState(() => _range = n)),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: SxSpace.s12),
          side(WhyText(_error!)),
        ],
        const SizedBox(height: SxSpace.s20),
      ],
    );
  }
}

class _NewProductSheet extends StatefulWidget {
  const _NewProductSheet({this.currency, required this.example});

  final String? currency;

  /// A product name typical for this kind of shop, shown as the hint.
  final String example;

  @override
  State<_NewProductSheet> createState() => _NewProductSheetState();
}

class _NewProductSheetState extends State<_NewProductSheet> {
  final _name = TextEditingController();
  final _variant = TextEditingController();
  final _price = TextEditingController();
  final _count = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _variant.dispose();
    _price.dispose();
    _count.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim());
    final count = int.tryParse(_count.text.trim());
    if (name.isEmpty) return setState(() => _error = 'Give the product a name.');
    if (price == null || price < 0) return setState(() => _error = 'Enter the price, like 450.');
    if (count == null || count < 1 || count > stepperMax) {
      return setState(() => _error = 'Enter how many, from 1 to $stepperMax.');
    }
    final variant = _variant.text.trim();
    Navigator.of(context).pop(
      _Entry(
        name: name,
        variant: variant.isEmpty ? null : variant,
        priceMinor: (price * 100).round(),
        currency: widget.currency ?? 'INR',
        count: count,
        isNew: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SxSpace.s12,
    children: [
      SxField(
        controller: _name,
        label: 'Name',
        hint: widget.example,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
      ),
      SxField(controller: _variant, label: 'Size or flavour (optional)', hint: '1 kg'),
      SxField(
        controller: _price,
        label: 'Price',
        hint: '450',
        prefix: '₹',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      SxField(
        controller: _count,
        label: 'How many',
        hint: '40',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        errorText: _error,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      const SizedBox(height: SxSpace.s4),
      SxButton(label: 'Add to the list', fullWidth: true, onTap: _done),
    ],
  );
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

  Future<void> _go() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _error = 'Write a count, a name and a price, like “10 ${widget.example.toLowerCase()} 450”.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lines = await ref.read(sellixApiProvider).parseStockText(text);
      if (!mounted) return;
      Navigator.of(context).pop(lines);
    } on Exception catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _error = sxErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SxField(
        controller: _text,
        maxLines: 4,
        autofocus: true,
        hint: '10 ${widget.example.toLowerCase()} 450',
        errorText: _error,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      const SizedBox(height: SxSpace.s16),
      SxButton(
        label: 'Make the list',
        icon: TablerIcons.sparkles,
        fullWidth: true,
        loading: _busy,
        onTap: _busy ? null : _go,
      ),
    ],
  );
}
