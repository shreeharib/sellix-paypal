import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../today/today_providers.dart';

final questionsProvider = FutureProvider.autoDispose.family<List<Question>, String>(
  (ref, status) => ref.watch(sellixApiProvider).questions(status: status),
);

/// The agent's questions for the merchant; answers go back to the customer through the agent.
class AskMeScreen extends ConsumerStatefulWidget {
  const AskMeScreen({super.key});

  @override
  ConsumerState<AskMeScreen> createState() => _AskMeScreenState();
}

class _AskMeScreenState extends ConsumerState<AskMeScreen> {
  String _status = 'open';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final questions = ref.watch(questionsProvider(_status));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navAskMe)),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'open', label: Text(l10n.askMeOpen)),
                  ButtonSegment(value: 'answered', label: Text(l10n.askMeAnswered)),
                ],
                selected: {_status},
                onSelectionChanged: (selection) => setState(() => _status = selection.first),
              ),
            ),
            Expanded(
              child: AsyncView(
                value: questions,
                onRetry: () => ref.invalidate(questionsProvider(_status)),
                data: (items) => items.isEmpty
                    ? MessageView(
                        icon: Icons.mark_chat_read_outlined,
                        title: l10n.askMeEmpty,
                        body: l10n.askMeEmptyHint,
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.refresh(questionsProvider(_status).future),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(Insets.md, 0, Insets.md, Insets.md),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Insets.sm),
                          itemBuilder: (context, index) => _QuestionCard(question: items[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final open = question.status == 'open';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Insets.radius),
        onTap: open ? () => _showAnswerSheet(context, question) : null,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(question.question, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Insets.sm),
              Text(
                formatDayTime(question.createdAt, locale),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (question.answer != null) ...[
                const Divider(height: Insets.lg),
                Text(context.l10n.askMeYourAnswer, style: theme.textTheme.labelMedium),
                const SizedBox(height: Insets.xs),
                Text(question.answer!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showAnswerSheet(BuildContext context, Question question) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AnswerSheet(question: question),
    );

class _AnswerSheet extends ConsumerStatefulWidget {
  const _AnswerSheet({required this.question});

  final Question question;

  @override
  ConsumerState<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends ConsumerState<_AnswerSheet> {
  final _answer = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(questionsProvider)
        ..invalidate(todayProvider);
      if (mounted) {
        showMessage(context, doneMessage);
        Navigator.of(context).pop();
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final api = ref.read(sellixApiProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.md,
        0,
        Insets.md,
        Insets.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ContentWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.question.question, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _answer,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: InputDecoration(hintText: l10n.askMeAnswerHint),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => api.dismissQuestion(widget.question.id), l10n.commonSaved),
                  child: Text(l10n.askMeDismiss),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final text = _answer.text.trim();
                          if (text.isEmpty) return;
                          _run(
                            () => api.answerQuestion(widget.question.id, text),
                            l10n.askMeAnswerSent,
                          );
                        },
                  child: Text(l10n.askMeSendAnswer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
