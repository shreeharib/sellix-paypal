import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_answers_text.dart';
import 'ob_categories.dart';
import 'ob_common.dart';

class ObRulesScreen extends ConsumerStatefulWidget {
  const ObRulesScreen({super.key});

  @override
  ConsumerState<ObRulesScreen> createState() => _ObRulesScreenState();
}

class _ObRulesScreenState extends ConsumerState<ObRulesScreen> with ObSaving {
  final _delivery = TextEditingController();
  final _custom = TextEditingController();
  bool _ready = false;
  ObCategory _category = obOtherCategory;
  String _categoryLabel = obOtherCategory.label;
  bool _hasPickup = false;
  final Set<String> _asksOff = {};
  int _bulk = 10;
  List<String> _neverOptions = const [];
  Set<String> _never = {};

  @override
  void dispose() {
    _delivery.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _load() {
    final draft = ref.watch(onboardingDraftProvider).value;
    if (_ready || draft == null) return;
    _ready = true;
    final a = draft.answers;
    _category = obCategoryOf(a.category) ?? obOtherCategory;
    _categoryLabel = a.category ?? _category.label;
    _hasPickup = (a.address ?? '').isNotEmpty;
    _bulk = _category.bulkLimit;

    _bulk = obParseBulk(obParseAsks(a.faqs), 'Bulk orders') ?? _bulk;
    _asksOff.addAll(obParseAlone(a.faqs));

    final savedNever = a.neverPromise?.split(', ').where((s) => s.isNotEmpty).toList();
    _neverOptions = [
      ..._category.never,
      ...?savedNever?.where((s) => !_category.never.contains(s)),
    ];
    _never = savedNever?.toSet() ?? _category.never.take(3).toSet();

    final place = (a.area ?? '').isNotEmpty ? a.area! : 'the shop';
    _delivery.text = a.fulfilment ??
        (_hasPickup
            ? 'Pickup from $place. We deliver nearby, the shop confirms the charge.'
            : 'We deliver to your door. The shop confirms the charge.');
    _custom.text = a.customOrders ?? '';
  }

  void _continue() {
    final asks = [
      for (final ask in _category.asks)
        if (ask.isBulk || !_asksOff.contains(ask.title))
          ask.isBulk ? obBulkAsk(ask.title, _bulk, _category.unit) : ask.title,
    ];
    saveThen(
      (a) => a.copyWith(
        neverPromise: _never.isEmpty ? null : [for (final n in _neverOptions) if (_never.contains(n)) n].join(', '),
        fulfilment: obText(_delivery.text),
        customOrders: obText(_custom.text),
        // BACKEND GAP: no structured rules; the asks are text the agent reads. See obFaqsWith.
        faqs: obFaqsWith(a.faqs, asks: asks, alone: [
          for (final ask in _category.asks)
            if (!ask.isBulk && _asksOff.contains(ask.title)) ask.title,
        ]),
      ),
      () => context.push(Routes.obHours),
    );
  }

  /// The stepper moves in fives, between 5 and 200.
  void _stepBulk(int next) {
    final delta = next > _bulk ? 5 : -5;
    setState(() => _bulk = (_bulk + delta).clamp(5, 200));
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final p = context.sx;
    final unit = _category.unit;
    return ObStepFrame(
      step: 1,
      fraction: 0.55,
      fallback: Routes.obTalk,
      title: 'When should sellix ask you?',
      why: 'sellix handles normal orders alone. For these, it pauses the chat and asks you.',
      saving: saving,
      onContinue: _ready ? _continue : null,
      onSkip: () => context.push(Routes.obHours),
      children: [
        const SizedBox(height: SxSpace.s12),
        SxFadeUp(
          index: 2,
          child: Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SxChip(label: _categoryLabel, icon: _category.icon),
              Text('Turn off what you do not need.', style: SxText.caption.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s12),
        SxFadeUp(
          index: 3,
          child: SxGroup(
            children: [
              for (final ask in _category.asks)
                if (ask.isBulk)
                  SxListRow(
                    title: ask.title,
                    subtitle: '${unit[0].toUpperCase()}${unit.substring(1)} in one order',
                    icon: ask.icon,
                    chevron: false,
                    trailing: SxStepper(
                      value: _bulk,
                      min: 5,
                      max: 200,
                      itemName: 'bulk order size',
                      onChanged: _stepBulk,
                    ),
                  )
                else
                  SxSwitchRow(
                    title: ask.title,
                    subtitle: ask.detail,
                    icon: ask.icon,
                    value: !_asksOff.contains(ask.title),
                    onChanged: (on) => setState(() {
                      on ? _asksOff.remove(ask.title) : _asksOff.add(ask.title);
                    }),
                  ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ObLabel('sellix never promises'),
              Wrap(
                spacing: SxSpace.s8,
                runSpacing: SxSpace.s8,
                children: [
                  for (final option in _neverOptions)
                    SxPickChip(
                      label: option,
                      selected: _never.contains(option),
                      onTap: () => setState(() {
                        _never = {..._never};
                        if (!_never.remove(option)) _never.add(option);
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        SxFadeUp(
          index: 5,
          child: SxField(
            controller: _delivery,
            label: _hasPickup ? 'Pickup and delivery' : 'Delivery',
            hint: 'How customers get their order',
            maxLines: 3,
            maxLength: 1500,
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        SxFadeUp(
          index: 6,
          child: SxField(
            controller: _custom,
            label: '${_category.customLabel} (optional)',
            hint: 'Example: 3 days’ notice, 50% advance',
            maxLines: 3,
            maxLength: 1500,
          ),
        ),
        const SizedBox(height: SxSpace.s16),
        const SxFadeUp(
          index: 7,
          child: SxAiNote(
            'I never guess a price, a discount or a delivery time. I ask you, and I tell the customer I am checking.',
          ),
        ),
      ],
    );
  }
}
