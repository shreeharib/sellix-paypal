import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'stock_actions.dart';
import 'stock_model.dart';
import 'stock_providers.dart';
import 'stock_widgets.dart';

/// Today's list. The prototype's voice flow, without the voice: the list starts from the catalogue
/// and today's counts, and typing a line fills it the way speaking would have.
class MorningScreen extends ConsumerStatefulWidget {
  const MorningScreen({super.key});

  @override
  ConsumerState<MorningScreen> createState() => _MorningScreenState();
}

class _Typed {
  const _Typed(this.text, this.found, this.fresh);

  final String text;
  final Map<String, int> found;
  final List<StockLine> fresh;
}

class _MorningScreenState extends ConsumerState<MorningScreen> {
  final _counts = <String, int>{};
  final _ids = <String>[];
  final _seen = <String>{};
  final _fresh = <String, StockItem>{};
  final _whys = <String, String>{};
  String? _typed;
  bool _saving = false;
  bool _done = false;

  Map<String, int> _carried(StockView view) =>
      ref.read(carriedLogProvider).read(view.today.businessDate);

  StockItem? _item(StockView view, String id) => view.byVariant(id) ?? _fresh[id];

  int _minNew(StockItem item, int carried) {
    final least = item.floor - carried - item.restocked;
    return least > 0 ? least : 0;
  }

  /// Adopts products this screen hasn't seen: everything at first, then one just added.
  void _sync(StockView view) {
    final carried = _carried(view);
    for (final item in view.tracked) {
      if (!_seen.add(item.variantId)) continue;
      _ids.add(item.variantId);
      final count = item.opening - (carried[item.variantId] ?? 0);
      _counts[item.variantId] = count > 0 ? count : 0;
    }
  }

  void _applyTyped(StockView view, _Typed typed) {
    final carried = _carried(view);
    setState(() {
      _typed = typed.text;
      _ids.clear();
      _counts.clear();
      _whys.clear();
      _fresh.clear();
      for (final MapEntry(:key, :value) in typed.found.entries) {
        final item = view.byVariant(key);
        if (item == null) continue;
        final least = _minNew(item, carried[key] ?? 0);
        _ids.add(key);
        _counts[key] = value > 0 && value < least ? least : value;
      }
      for (final line in typed.fresh) {
        final id = 'new:${line.label}';
        _fresh[id] = StockItem(
          variantId: id,
          productId: null,
          name: line.product,
          variant: line.variant,
          priceMinor: line.priceMinor,
          currency: line.currency,
          stockMode: StockMode.daily,
          shelfLifeDays: null,
        );
        _ids.add(id);
        _counts[id] = line.quantity > stepperMax ? stepperMax : line.quantity;
      }
    });
  }

  Future<void> _typeIt(StockView view) async {
    final terms = ShopTerms.of(ref.read(shopAnswersProvider).value?.category);
    final typed = await showSxSheet<_Typed>(
      context,
      title: 'Type today’s stock',
      subtitle: 'One line is fine. Write the count, then the name.',
      builder: (_) => _TypeSheet(view: view, example: terms.exampleProduct),
    );
    if (typed != null && mounted) _applyTyped(view, typed);
  }

  Future<void> _addMissed(StockView view) async {
    final carried = _carried(view);
    final missing = view.tracked.where((i) => !_ids.contains(i.variantId)).toList();
    final picked = await showSxSheet<String>(
      context,
      title: 'Add an item',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          for (final item in missing)
            SxChoiceCard(
              title: item.label,
              subtitle: '${item.priceLabel} · ${item.shelf}',
              icon: TablerIcons.package,
              onTap: () => Navigator.of(sheet).pop(item.variantId),
            ),
          SxChoiceCard(
            title: 'New product',
            icon: TablerIcons.camera_plus,
            onTap: () => Navigator.of(sheet).pop('+new'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == '+new') {
      await context.push(Routes.addproduct);
      return;
    }
    final item = view.byVariant(picked);
    if (item == null) return;
    final least = _minNew(item, carried[picked] ?? 0);
    HapticFeedback.lightImpact();
    setState(() {
      _ids.add(picked);
      _counts[picked] = least > 1 ? least : 1;
    });
  }

  List<StockLine> _lines(StockView view) {
    final carried = _carried(view);
    return [
      for (final id in _ids)
        if (_fresh[id] case final fresh?)
          if ((_counts[id] ?? 0) > 0) fresh.line(_counts[id]!),
      for (final id in _ids)
        if (view.byVariant(id) case final item?)
          // PUT replaces opening, which also holds what was carried. Unchanged lines stay out.
          if ((_counts[id] ?? 0) + (carried[id] ?? 0) != item.opening)
            item.line((_counts[id] ?? 0) + (carried[id] ?? 0)),
      // Left off the list and nothing sold: it really goes off today's list.
      for (final item in view.tracked)
        if (!_ids.contains(item.variantId) &&
            item.row != null &&
            item.floor == 0 &&
            item.restocked == 0 &&
            item.opening != (carried[item.variantId] ?? 0))
          item.line(carried[item.variantId] ?? 0),
    ];
  }

  Future<void> _confirm(StockView view) async {
    if (_saving || _done) return;
    final carried = _carried(view);
    final any =
        _ids.any((id) {
          final item = _item(view, id);
          return (_counts[id] ?? 0) + (carried[id] ?? 0) + (item?.restocked ?? 0) > 0;
        }) ||
        carried.values.any((v) => v > 0) ||
        view.noCount.isNotEmpty;
    if (!any) {
      HapticFeedback.heavyImpact();
      showSxSnack(context, 'No counts yet. Type what you have today, or set a count below.', icon: TablerIcons.keyboard);
      return;
    }
    for (final id in _ids) {
      final item = view.byVariant(id);
      if (item == null) continue;
      final least = _minNew(item, carried[id] ?? 0);
      if ((_counts[id] ?? 0) < least) {
        HapticFeedback.heavyImpact();
        setState(() => _whys[id] = '${item.floorWhy}. Set at least $least here.');
        return;
      }
    }
    final lines = _lines(view);
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    final actions = StockActions(context);
    try {
      if (lines.isNotEmpty) await ref.read(sellixApiProvider).setOpeningStock(lines);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      HapticFeedback.heavyImpact();
      showSxSnack(context, sxErrorMessage(error), icon: TablerIcons.alert_circle);
      return;
    }
    actions.refresh();
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _saving = false;
      _done = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    context.go(Routes.home);
    await Future<void>.delayed(SxMotion.slow);
    // The agent's on or off switch stays the merchant's: confirming a list doesn't turn sellix on.
    actions.announce(view.today.agentEnabled ? 'Stock is live.' : 'Stock is saved. sellix is paused.', icon: TablerIcons.check);
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.stock);

  Widget _top(StockView? view) => Padding(
    padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s8, SxSpace.screen, 0),
    child: Row(
      children: [
        SxIconButton(icon: TablerIcons.x, semanticLabel: 'Close', onTap: _close),
        const SizedBox(width: SxSpace.s12),
        if (view != null)
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: SxSpace.s8,
              runSpacing: SxSpace.s4,
              children: [
                SxChip(label: DateFormat('EEE, d MMM').format(view.today.businessDate), icon: TablerIcons.calendar),
                view.today.agentEnabled
                    ? const SxLivePill(state: SxAgentState.live, label: 'Live')
                    : const SxLivePill(state: SxAgentState.paused, label: 'Paused'),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(stockViewProvider);
    final view = value.value;
    final empty = view != null && view.items.isEmpty;
    return SxScaffold(
      floating: view == null
          ? null
          : empty
          ? SxBottomCta(
              label: 'Add product',
              icon: TablerIcons.plus,
              onTap: () => context.push(Routes.addproduct),
            )
          : SxBottomCta(
              label: _done ? 'You are live' : (_saving ? 'Going live…' : 'Confirm and go live'),
              loading: _saving,
              done: _done,
              onTap: () => _confirm(view),
            ),
      body: Column(
        children: [
          _top(view),
          Expanded(
            child: SxAsyncView<StockView>(
              value: value,
              onRetry: () {
                ref.invalidate(todayProvider);
                ref.invalidate(catalogProvider);
              },
              loading: const SxSkeletonList(topHeight: 160),
              isEmpty: (v) => v.items.isEmpty,
              empty: const SxEmptyState(
                icon: TablerIcons.package,
                title: 'Add your first product',
                body: 'A name, a price and how long you can sell it. You need one product to go live.',
              ),
              builder: (context, view) {
                _sync(view);
                return _body(view);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(StockView view) {
    final p = context.sx;
    final answers = ref.watch(shopAnswersProvider).value;
    final terms = ShopTerms.of(answers?.category);
    final carried = _carried(view);
    final hasTracked = view.tracked.isNotEmpty;
    final hint = _ids.take(2).map((id) => '5 ${_item(view, id)?.label.toLowerCase()}').join(', ');
    final missed = view.tracked.where((i) => !_ids.contains(i.variantId)).toList();
    Widget side(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen),
      child: child,
    );
    return SxScrollList(
      onRefresh: () async {
        ref.invalidate(leftoversProvider);
        ref.invalidate(todayProvider);
        ref.invalidate(catalogProvider);
        await ref.read(stockViewProvider.future);
      },
      children: [
        const SizedBox(height: SxSpace.s20),
        side(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(terms.stockQuestion, style: SxText.titleL.copyWith(color: p.textPrimary)),
              const SizedBox(height: SxSpace.s8),
              Text(
                'Type a count and a name. sellix makes the list. You fix the counts.',
                style: SxText.caption.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        side(const LeftoversRow()),
        if (hasTracked) ...[
          side(
            // BACKEND GAP: no transcription endpoint, so the card stays and the mic is off.
            SxVoiceCard(
              stateLabel: _typed != null ? 'Got it. Check the counts.' : 'Voice isn’t ready yet. Type your list instead.',
              stateIcon: _typed != null ? TablerIcons.check : TablerIcons.microphone_off,
              transcript: _typed == null ? null : '“$_typed”',
              placeholder: hint.isEmpty ? 'Type a count and a name.' : '“$hint…”',
              onMic: null,
              micLabel: 'Voice is not available yet',
            ),
          ),
          const SizedBox(height: SxSpace.s12),
          SxFilterChips(
            children: [
              SxFilterChip(
                label: 'Type it',
                icon: TablerIcons.keyboard,
                selected: false,
                onTap: () => _typeIt(view),
              ),
              // BACKEND GAP: no endpoint returns yesterday's list. Leftovers hold only unsold units.
              const SxFilterChip(label: 'Same as yesterday', icon: TablerIcons.copy, selected: false, onTap: null),
              // BACKEND GAP: no photo upload or recognition endpoint.
              const SxFilterChip(label: 'Photo', icon: TablerIcons.camera, selected: false, onTap: null),
            ],
          ),
          const SizedBox(height: SxSpace.s8),
          side(
            Text(
              'Same as yesterday and Photo aren’t ready yet.',
              style: SxText.micro.copyWith(color: p.textSecondary),
            ),
          ),
          if (_ids.isNotEmpty)
            SxSectionHeader(
              title: '${_typed != null ? 'sellix found' : 'Your list:'} ${plural(_ids.length, 'item', 'items')}',
            )
          else
            const SizedBox(height: SxSpace.s16),
          side(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.listGap,
              children: [
                for (final (i, id) in _ids.indexed)
                  if (_item(view, id) case final item?)
                    SxFadeUp(
                      index: i,
                      child: _row(item, carried[id] ?? 0, _fresh.containsKey(id)),
                    ),
                SxRowCard(
                  title: 'Add a missed item',
                  icon: TablerIcons.plus,
                  outlined: true,
                  chevron: false,
                  onTap: () => _addMissed(view),
                ),
              ],
            ),
          ),
          if (_typed != null && missed.isNotEmpty) ...[
            const SizedBox(height: SxSpace.s12),
            side(SxAiNote(_missedNote(missed))),
          ],
        ],
        if (view.noCount.isNotEmpty) ...[
          const SizedBox(height: SxSpace.s16),
          side(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.listGap,
              children: [
                Text('No count needed', style: SxText.label.copyWith(color: p.textPrimary)),
                for (final item in view.noCount)
                  SxRowCard(
                    title: item.label,
                    meta: '${item.shelf}. ${noCountWhy(item.stockMode)}',
                    leading: const SxIconTile(icon: TablerIcons.package),
                    chevron: false,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _missedNote(List<StockItem> missed) {
    final names =
        missed.take(2).map((i) => i.label).join(' and ') +
        (missed.length > 2 ? ' and ${missed.length - 2} more' : '');
    final many = missed.length > 1;
    return '$names ${many ? 'are' : 'is'} in your catalogue but you did not list ${many ? 'them' : 'it'}. '
        'I left ${many ? 'them' : 'it'} out today.';
  }

  Widget _row(StockItem item, int carried, bool isNew) {
    final value = _counts[item.variantId] ?? 0;
    final total = value + carried + item.restocked;
    final least = _minNew(item, carried);
    final String? meta = total == 0
        ? null
        : isNew
        ? 'New · ${money(item.priceMinor, item.currency)}'
        : carried > 0
        ? '+$carried carried · $total today'
        : item.restocked > 0
        ? '+${item.restocked} added · $total today'
        : item.priceLabel;
    return WhyStockRow(
      title: item.label,
      meta: meta,
      chip: total == 0 ? const SxChip(label: 'Not today') : null,
      value: value,
      min: least,
      whyMin: least > 0
          ? '${item.floorWhy}${carried > 0 ? ', $carried carried' : ''}. You can’t go below $least here.'
          : 'Zero keeps it off today’s list.',
      whyMax: 'The most you can set is $stepperMax.',
      externalWhy: _whys[item.variantId],
      onChanged: (v) => setState(() {
        _counts[item.variantId] = v;
        _whys.remove(item.variantId);
      }),
    );
  }
}

class _TypeSheet extends ConsumerStatefulWidget {
  const _TypeSheet({required this.view, required this.example});

  final StockView view;
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

  StockItem? _matchLine(StockLine line) {
    final product = line.product.toLowerCase();
    final variant = line.variant?.toLowerCase();
    for (final item in widget.view.tracked) {
      final name = item.name.toLowerCase();
      final own = item.variant?.toLowerCase();
      if (name == product && own == variant) return item;
      if (variant == null && own != null && product == '$name $own') return item;
    }
    for (final item in widget.view.tracked) {
      if (variant != null) continue;
      if (item.name.toLowerCase() == product ||
          item.aliases.any((a) => a.aliasText.toLowerCase() == product)) {
        return item;
      }
    }
    return null;
  }

  /// `parse-stock-text` first, since it can also read new items with their prices. It refuses a line
  /// with no price, so a plain "5 kurti" falls back to matching the shop's own names here.
  Future<void> _go() async {
    final text = _text.text.trim();
    final notFound = 'No products found in that. Write a count and a name, like “5 ${widget.example.toLowerCase()}”.';
    if (text.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _error = notFound);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final found = <String, int>{};
    final fresh = <StockLine>[];
    try {
      final lines = await ref
          .read(sellixApiProvider)
          .parseStockText(text, defaultCurrency: widget.view.currency);
      for (final line in lines) {
        final item = _matchLine(line);
        if (item != null) {
          // The catalogue keeps its price: typing a count must not change one quietly.
          found[item.variantId] = line.quantity > stepperMax ? stepperMax : line.quantity;
        } else if (line.priceMinor > 0) {
          fresh.add(line);
        }
      }
    } on ApiException {
      found.addAll(matchStockText(text, widget.view.tracked));
    }
    if (!mounted) return;
    if (found.isEmpty && fresh.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _error = notFound;
      });
      return;
    }
    Navigator.of(context).pop(_Typed(text, found, fresh));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SxField(
        controller: _text,
        maxLines: 4,
        autofocus: true,
        hint: '5 ${widget.example.toLowerCase()}',
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
