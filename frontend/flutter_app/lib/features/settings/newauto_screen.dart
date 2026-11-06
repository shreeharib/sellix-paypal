import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'automation_widgets.dart';
import 'automations_store.dart';
import 'settings_providers.dart';

enum _Source { template, own }

const _actions = [
  ('msg', 'Sends a message'),
  ('prod', 'Sends a product'),
  ('pay', 'Sends a payment link'),
  ('ask', 'Asks you first'),
];

class NewAutoScreen extends ConsumerStatefulWidget {
  const NewAutoScreen({super.key});

  @override
  ConsumerState<NewAutoScreen> createState() => _NewAutoScreenState();
}

class _NewAutoScreenState extends ConsumerState<NewAutoScreen> {
  _Source _source = _Source.template;
  String? _template;
  AutomationTrigger? _trigger;
  String _action = 'msg';
  bool _done = false;
  final _message = TextEditingController(text: '{name}, {product} is back today. Shall I keep some for you?');

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _insert(String variable) {
    final text = _message.text;
    final selection = _message.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _message.value = TextEditingValue(
      text: text.replaceRange(start, end, variable),
      selection: TextSelection.collapsed(offset: start + variable.length),
    );
    setState(() {});
  }

  /// BACKEND GAP: nothing can run this yet, so the prototype's "Turn on" saves on the phone and says so.
  Future<void> _save() async {
    final notifier = ref.read(automationsProvider.notifier);
    if (_source == _Source.own) {
      final trigger = _trigger;
      if (trigger == null) {
        showSxSnack(context, 'Pick what starts it first.', icon: TablerIcons.hand_click);
        return;
      }
      final message = _message.text.trim();
      if (message.isEmpty) {
        showSxSnack(context, 'Write the message first.', icon: TablerIcons.pencil);
        return;
      }
      await notifier.addCustom(
        trigger: trigger.title,
        channel: trigger.channel,
        message: message,
        action: _actions.firstWhere((a) => a.$1 == _action).$2,
        preview: message,
      );
    } else {
      final template = _template;
      if (template == null) {
        showSxSnack(context, 'Pick a template first.', icon: TablerIcons.hand_click);
        return;
      }
      await notifier.setOn(template, true);
    }
    if (!mounted) return;
    setState(() => _done = true);
    await finishSave(context, '$automationLocalNote.', fallback: Routes.automations);
  }

  @override
  Widget build(BuildContext context) {
    final automations = ref.watch(automationsProvider);
    final fill = automationFiller(ref);
    return SxScaffold(
      floating: automations.hasValue
          ? SxBottomCta(
              label: _done ? 'Saved' : 'Save on this phone',
              icon: TablerIcons.device_mobile,
              done: _done,
              onTap: _done ? null : _save,
            )
          : null,
      body: Column(
        children: [
          const SxDetailHeader(title: 'New automation', fallback: Routes.automations),
          Expanded(
            child: SxAsyncView<List<Automation>>(
              value: automations,
              onRetry: () => ref.invalidate(meProvider),
              loading: const SxSkeletonList(topHeight: 48, itemHeight: 180, count: 3),
              builder: (context, list) => SxScrollList(
                children: [
                  Mx(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: SxSpace.s12,
                      children: [
                        const SxLocalOnlyNote(),
                        SxSegmented<_Source>(
                          segments: const [
                            SxSegment(_Source.template, 'Use a template'),
                            SxSegment(_Source.own, 'Build your own'),
                          ],
                          value: _source,
                          onChanged: (v) => setState(() => _source = v),
                        ),
                        if (_source == _Source.template) ..._templates(list) else ..._own(fill),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _templates(List<Automation> list) {
    final p = context.sx;
    final templates = list.where((a) => !a.locked && !a.custom && (!a.on || a.group == AutomationGroup.grow));
    return [
      for (final (i, a) in templates.indexed)
        SxFadeUp(
          index: i,
          child: SxPressable(
            onTap: () => setState(() => _template = a.id),
            semanticLabel: a.title,
            child: AnimatedContainer(
              duration: SxMotion.base,
              padding: const EdgeInsets.all(SxSpace.card),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(SxRadius.card),
                border: Border.all(color: _template == a.id ? p.textPrimary : p.card, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AutomationMiniChat(lines: a.chat),
                  const SizedBox(height: SxSpace.s12),
                  Row(
                    spacing: SxSpace.s8,
                    children: [
                      Expanded(child: Text(a.title, style: SxText.bodyStrong.copyWith(color: p.textPrimary))),
                      if (a.popular) const SxChip(label: 'Popular'),
                    ],
                  ),
                  const SizedBox(height: SxSpace.s4),
                  Text(a.description, style: SxText.caption.copyWith(color: p.textSecondary)),
                  const SizedBox(height: SxSpace.s8),
                  Row(
                    spacing: SxSpace.s12,
                    children: [
                      for (final brand in a.channels)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: SxSpace.s4,
                          children: [
                            SxBrandIcon(brand, size: 16, color: p.textSecondary),
                            Text(brandName(brand), style: SxText.micro.copyWith(color: p.textSecondary)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: SxSpace.s8),
                  const AutomationLocalTag(),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _own(String Function(String) fill) {
    final p = context.sx;
    Widget step(String micro, String title) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(micro, style: SxText.micro.copyWith(color: p.textSecondary)),
        const SizedBox(height: SxSpace.s4),
        Text(title, style: SxText.titleM.copyWith(color: p.textPrimary)),
      ],
    );
    return [
      step('Step 1', 'When this happens'),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - SxSpace.s8) / 2;
          return Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final t in automationTriggers)
                SizedBox(
                  width: width,
                  child: SxPressable(
                    onTap: () => setState(() => _trigger = t),
                    semanticLabel: t.title,
                    child: AnimatedContainer(
                      duration: SxMotion.base,
                      constraints: const BoxConstraints(minHeight: 118),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.card,
                        borderRadius: BorderRadius.circular(SxRadius.bubble),
                        border: Border.all(color: _trigger == t ? p.textPrimary : p.card, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: SxSpace.s8,
                        children: [
                          SxIconTile(icon: t.icon, size: 40),
                          Text(t.title, style: SxText.label.copyWith(color: p.textPrimary)),
                          Text(t.channel, style: SxText.micro.copyWith(color: p.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      if (_trigger != null) ...[
        const SizedBox(height: SxSpace.s12),
        step('Step 2', 'sellix does'),
        Wrap(
          spacing: SxSpace.s8,
          runSpacing: SxSpace.s8,
          children: [
            for (final (value, label) in _actions)
              SxPickChip(label: label, selected: _action == value, onTap: () => setState(() => _action = value)),
          ],
        ),
        const SizedBox(height: SxSpace.s12),
        step('Step 3', 'Message'),
        SxField(
          controller: _message,
          maxLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final variable in const ['{name}', '{product}', '{price}', '{left}'])
              SxPickChip(label: variable, selected: false, onTap: () => _insert(variable)),
          ],
        ),
        const SxAiNote('I rewrite this in each customer’s language and fill in the real price and stock.'),
        Container(
          padding: const EdgeInsets.all(SxSpace.card),
          decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(SxRadius.bubble)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              Text('Preview', style: SxText.micro.copyWith(color: p.textSecondary)),
              SxBubble(text: fill(_message.text), sender: SxBubbleSender.sellix),
            ],
          ),
        ),
      ],
    ];
  }
}
