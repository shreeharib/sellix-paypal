import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'automation_widgets.dart';
import 'automations_store.dart';
import 'settings_providers.dart';

class AutomationScreen extends ConsumerStatefulWidget {
  const AutomationScreen(this.automationId, {super.key});

  final String automationId;

  @override
  ConsumerState<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends ConsumerState<AutomationScreen> {
  // Edits wait for "Save changes".
  AutomationMode? _mode;
  int? _wait;
  List<String>? _words;
  bool _done = false;

  Automation? _find(List<Automation>? list) {
    for (final a in list ?? const <Automation>[]) {
      if (a.id == widget.automationId) return a;
    }
    return null;
  }

  Future<void> _save(Automation saved) async {
    final next = saved.copyWith(mode: _mode, waitMinutes: _wait, words: _words);
    await ref.read(automationsProvider.notifier).saveSettings(next);
    if (!mounted) return;
    setState(() => _done = true);
    await finishSave(context, '$automationLocalNote.', fallback: Routes.automations);
  }

  Future<void> _addWord(List<String> words) async {
    final word = await showSxSheet<String>(
      context,
      title: 'Add a word to watch',
      subtitle: 'When a comment has this word, sellix sends the price in a DM.',
      builder: (_) => const _WordSheet(),
    );
    if (word == null || !mounted) return;
    setState(() => _words = [...words, word]);
  }

  @override
  Widget build(BuildContext context) {
    final automations = ref.watch(automationsProvider);
    final a = _find(automations.value);
    return SxScaffold(
      floating: a == null || a.locked
          ? null
          : SxBottomCta(
              label: _done ? 'Saved' : 'Save changes',
              icon: TablerIcons.check,
              done: _done,
              onTap: _done ? null : () => _save(a),
            ),
      body: Column(
        children: [
          SxDetailHeader(title: a?.title ?? 'Automation', meta: a?.channelNames, fallback: Routes.automations),
          Expanded(
            child: SxAsyncView<List<Automation>>(
              value: automations,
              onRetry: () => ref.invalidate(meProvider),
              loading: const SxSkeletonList(topHeight: 80, count: 3),
              isEmpty: (list) => _find(list) == null,
              empty: const SxEmptyState(
                icon: TablerIcons.bolt_off,
                title: 'Automation not found',
                body: 'It may have been saved on another phone.',
              ),
              builder: (context, list) => _list(context, _find(list)!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, Automation saved) {
    final p = context.sx;
    final mode = _mode ?? saved.mode;
    final wait = _wait ?? saved.waitMinutes;
    final words = _words ?? saved.words;
    final view = saved.copyWith(mode: mode, waitMinutes: wait, words: words);
    final agentOn = ref.watch(meProvider).value?.merchant.agentEnabled ?? true;
    final steps = view.flow;

    return SxScrollList(
      children: [
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!saved.locked) ...[const SxLocalOnlyNote(), const SizedBox(height: SxSpace.s12)],
              SxFadeUp(
                child: SxCard(
                  child: Row(
                    spacing: SxSpace.s12,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              saved.locked ? (agentOn ? 'Running' : 'Agent paused') : (saved.on ? 'On' : 'Off'),
                              style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                            ),
                            Text(
                              saved.locked
                                  ? 'Built into sellix. Follows the agent switch in Profile.'
                                  : (saved.on ? 'Not active yet' : 'Turn on to save your choice'),
                              style: SxText.caption.copyWith(color: p.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (saved.locked)
                        const SxChip(label: 'Always on', icon: TablerIcons.lock)
                      else
                        SxToggle(
                          value: saved.on,
                          semanticLabel: saved.title,
                          onChanged: (v) => toggleAutomation(context, saved, v),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SxSectionHeader(title: 'What customers see'),
        Mx(
          child: SxFadeUp(
            index: 1,
            child: SxCard(child: AutomationMiniChat(lines: saved.chat)),
          ),
        ),
        const SxSectionHeader(title: 'How it works'),
        Mx(
          child: SxFadeUp(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, step) in steps.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 37),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(width: 2, height: 22, color: p.lineStrong),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: SxSpace.card, vertical: 14),
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(SxRadius.bubble)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: SxSpace.s12,
                      children: [
                        SxIconTile(icon: step.icon, size: 40),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(step.tag, style: SxText.caption.copyWith(color: p.textSecondary)),
                              Text(step.text, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!saved.locked) ...[
          const SxSectionHeader(title: 'Mode'),
          Mx(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.s8,
              children: [
                SxSegmented<AutomationMode>(
                  segments: const [
                    SxSegment(AutomationMode.auto, 'Autopilot'),
                    SxSegment(AutomationMode.draft, 'Draft first'),
                  ],
                  value: mode,
                  onChanged: (v) => setState(() => _mode = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SxSpace.s4),
                  child: Text(
                    mode == AutomationMode.auto
                        ? 'sellix sends on its own.'
                        : 'sellix writes the message. You approve it in one tap.',
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (saved.id == 'pay') ...[
          const SxSectionHeader(title: 'Settings'),
          Mx(
            child: SxCard(
              child: Row(
                spacing: SxSpace.s12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Wait before reminding', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                        Text('Minutes after the link is sent', style: SxText.caption.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                  // The prototype's steps are 5 minutes, from 5 to 60.
                  SxStepper(
                    value: wait,
                    min: 5,
                    max: 60,
                    itemName: 'wait minutes',
                    onChanged: (v) => setState(() {
                      final up = v > wait;
                      _wait = (wait + (up ? 5 : -5)).clamp(5, 60);
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (saved.id == 'comment') ...[
          const SxSectionHeader(title: 'Words to watch'),
          Mx(
            child: Wrap(
              spacing: SxSpace.s8,
              runSpacing: SxSpace.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final word in words) SxChip(label: word),
                SxPickChip(label: 'Add', icon: TablerIcons.plus, selected: false, onTap: () => _addWord(words)),
              ],
            ),
          ),
        ],
        const SxSectionHeader(title: 'Last 7 days'),
        Mx(
          child: SxCard(
            // BACKEND GAP: no per-automation numbers (sent, became orders, sales).
            child: Text(
              saved.locked
                  ? 'Numbers for this are not available yet.'
                  : 'No numbers. This automation is not running yet.',
              style: SxText.bodyS.copyWith(color: p.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

class _WordSheet extends StatefulWidget {
  const _WordSheet();

  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  final _word = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  void _save() {
    final word = _word.text.trim();
    if (word.isEmpty) {
      setState(() => _error = 'Type a word first');
      return;
    }
    Navigator.of(context).pop(word);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SxSpace.s16,
    children: [
      SxField(controller: _word, hint: 'Type a word', autofocus: true, errorText: _error, onSubmitted: (_) => _save()),
      SxButton(label: 'Add word', fullWidth: true, onTap: _save),
    ],
  );
}
