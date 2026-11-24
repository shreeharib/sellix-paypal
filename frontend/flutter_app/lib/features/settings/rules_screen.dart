import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'saved_rules.dart';
import 'settings_providers.dart';

/// Reads the newest profile, changes only its saved answers, and writes a new version. Reading first
/// means a question answered elsewhere, or a rewrite from onboarding answers, is not overwritten.
Future<void> _writeRules(
  ProviderContainer container,
  List<SavedRule> Function(List<SavedRule> current) change,
) async {
  final api = container.read(sellixApiProvider);
  final current = await api.shopProfile();
  final title = current == null ? (await api.me()).merchant.name : '';
  final next = withSavedRules(
    current?.contentMd,
    change(parseSavedRules(current?.contentMd)),
    fallbackTitle: title.isEmpty ? 'My shop' : title,
  );
  if (next.length > shopProfileLimit) {
    throw const ApiException('The shop profile is full. Delete a rule or shorten this answer.');
  }
  await api.saveShopProfile(next);
  container.invalidate(shopProfileProvider);
}

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  Future<void> _edit(BuildContext context, SavedRule? rule) async {
    final container = containerOf(context);
    final saved = await showSxSheet<bool>(
      context,
      title: rule == null ? 'Add a rule' : 'Edit rule',
      subtitle: 'sellix gives this answer and does not ask you.',
      builder: (_) => _RuleSheet(rule: rule, container: container),
    );
    if (saved != true || !context.mounted) return;
    showSxSnack(
      context,
      rule == null ? 'Rule added. sellix will answer this alone.' : 'Rule saved.',
      icon: TablerIcons.bookmark,
    );
  }

  Future<void> _delete(BuildContext context, SavedRule rule, int index) async {
    final container = containerOf(context);
    try {
      await _writeRules(container, (rules) => [...rules]..removeWhere((r) => r.raw == rule.raw));
    } on ApiException catch (error) {
      if (context.mounted) showSxSnack(context, sxErrorMessage(error));
      return;
    }
    if (!context.mounted) return;
    showSxSnack(
      context,
      'Rule deleted. sellix will ask you next time.',
      icon: TablerIcons.trash,
      action: 'Undo',
      onAction: () async {
        try {
          await _writeRules(container, (rules) {
            final at = index.clamp(0, rules.length);
            return [...rules]..insert(at, rule);
          });
        } on ApiException catch (error) {
          if (context.mounted) showSxSnack(context, sxErrorMessage(error));
        }
      },
    );
  }

  /// A saved "always" answer: ask first, then `DELETE /v1/rules/{id}`.
  Future<void> _deleteAlways(BuildContext context, MerchantRule rule) async {
    final container = containerOf(context);
    final yes = await showSxConfirm(
      context,
      title: 'Delete this answer?',
      body: '“${rule.text}”\n\nsellix stops giving it, and asks you the next time someone asks.',
      confirmLabel: 'Delete',
      confirmIcon: TablerIcons.trash,
    );
    if (!yes) return;
    try {
      await container.read(sellixApiProvider).deleteRule(rule.id);
      container.invalidate(merchantRulesProvider);
    } on ApiException catch (error) {
      if (context.mounted) showSxSnack(context, sxErrorMessage(error));
      return;
    }
    if (context.mounted) {
      showSxSnack(context, 'Answer deleted. sellix will ask you next time.', icon: TablerIcons.trash);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(shopProfileProvider);
    return SxScaffold(
      floating: profile.hasValue
          ? SxBottomCta(label: 'Add a rule', icon: TablerIcons.plus, onTap: () => _edit(context, null))
          : null,
      body: Column(
        children: [
          const SxDetailHeader(title: 'Saved rules', meta: 'sellix answers these alone', fallback: Routes.profile),
          Expanded(
            child: SxAsyncView<ShopProfile?>(
              value: profile,
              onRetry: () => ref.invalidate(shopProfileProvider),
              loading: const SxSkeletonList(count: 3, itemHeight: 140),
              builder: (context, data) => _list(context, ref, parseSavedRules(data?.contentMd)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<SavedRule> rules) {
    final p = context.sx;
    final always = ref.watch(merchantRulesProvider);
    Future<void> refresh() {
      ref.invalidate(merchantRulesProvider);
      return ref.refresh(shopProfileProvider.future);
    }

    return SxScrollList(
      onRefresh: refresh,
      children: [
        if (rules.isEmpty && (always.value?.isEmpty ?? true))
          const Padding(
            padding: EdgeInsets.only(top: SxSpace.s48),
            child: SxEmptyState(
              icon: TablerIcons.bookmark,
              title: 'No rules yet',
              body: 'Add one here, or save an answer as a rule when sellix asks you.',
            ),
          ),
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              for (final (i, rule) in rules.indexed)
                SxFadeUp(
                  index: i,
                  child: SxCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('When someone asks', style: SxText.caption.copyWith(color: p.textSecondary)),
                        Text(rule.question, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                        if (rule.answer.isNotEmpty) ...[
                          const SizedBox(height: SxSpace.s8),
                          SxAiNote(rule.answer),
                        ],
                        const SizedBox(height: SxSpace.s4),
                        // BACKEND GAP: no source or usage count for a rule, so "From … · used N times" is gone.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: SxSpace.s8,
                          children: [
                            SxIconButton(
                              icon: TablerIcons.pencil,
                              semanticLabel: 'Edit rule',
                              onTap: () => _edit(context, rule),
                            ),
                            SxIconButton(
                              icon: TablerIcons.trash,
                              semanticLabel: 'Delete rule',
                              onTap: () => _delete(context, rule, i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SxSectionHeader(title: 'Saved from chats'),
        Mx(
          child: switch (always) {
            AsyncValue(value: final list?) when list.isEmpty => Text(
              'When you answer a question with “always answer this way”, it shows here.',
              style: SxText.caption.copyWith(color: p.textSecondary),
            ),
            AsyncValue(value: final list?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.s8,
              children: [
                for (final rule in list)
                  SxCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: SxSpace.s8,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: SxSpace.s4,
                            children: [
                              Text(rule.text, style: SxText.bodyS.copyWith(color: p.textPrimary)),
                              Text(
                                'Saved ${formatDate(rule.createdAt)}',
                                style: SxText.caption.copyWith(color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        SxIconButton(
                          icon: TablerIcons.trash,
                          semanticLabel: 'Delete saved answer',
                          onTap: () => _deleteAlways(context, rule),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            AsyncValue(hasError: true) => SxErrorState(
              error: always.error,
              onRetry: () => ref.invalidate(merchantRulesProvider),
            ),
            _ => const SxSkeleton(height: 72, radius: SxRadius.card),
          },
        ),
      ],
    );
  }
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.rule, required this.container});

  final SavedRule? rule;
  final ProviderContainer container;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final _question = TextEditingController(text: widget.rule?.question ?? '');
  late final _answer = TextEditingController(text: widget.rule?.answer ?? '');
  String? _questionError;
  String? _answerError;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = _question.text.trim();
    final a = _answer.text.trim();
    setState(() {
      _questionError = q.isEmpty ? 'Type what customers ask' : null;
      _answerError = a.isEmpty ? 'Type what sellix says' : null;
      _saveError = null;
    });
    if (q.isEmpty || a.isEmpty) return;
    setState(() => _saving = true);
    final old = widget.rule;
    final written = SavedRule.written(q, a);
    try {
      await _writeRules(widget.container, (rules) {
        final at = old == null ? -1 : rules.indexWhere((r) => r.raw == old.raw);
        return at < 0 ? [written, ...rules] : ([...rules]..[at] = written);
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = sxErrorMessage(error);
      });
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        SxField(
          controller: _question,
          label: 'When someone asks',
          hint: 'Do you deliver on Sunday?',
          errorText: _questionError,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
        ),
        SxField(
          controller: _answer,
          label: 'sellix says',
          hint: 'Yes, before 2 PM.',
          errorText: _answerError,
          maxLines: 3,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
        ),
        if (_saveError != null) SxBanner(tone: SxBannerTone.error, message: _saveError!),
        SxButton(
          label: widget.rule == null ? 'Add rule' : 'Save rule',
          fullWidth: true,
          loading: _saving,
          onTap: _save,
        ),
      ],
    );
  }
}
