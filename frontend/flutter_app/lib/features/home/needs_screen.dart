import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import 'home_providers.dart';
import 'home_widgets.dart';

/// The queue of everything sellix could not answer.
class NeedsScreen extends ConsumerStatefulWidget {
  const NeedsScreen({super.key});

  @override
  ConsumerState<NeedsScreen> createState() => _NeedsScreenState();
}

class _NeedsScreenState extends ConsumerState<NeedsScreen> {
  var _tab = 'open';

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    final value = ref.watch(homeDataProvider);
    final data = value.value;
    if (data != null) pushNavBadges(context, ref, data);
    final n = data?.openQuestions.length;
    return SxScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SxDetailHeader(
            title: 'Needs you',
            fallback: Routes.home,
            meta: n == null
                ? null
                : n > 0
                ? '$n need${n == 1 ? 's' : ''} you · customers are waiting'
                : 'Nobody is waiting',
          ),
          HomeMargin(
            child: SxSegmented<String>(
              segments: const [SxSegment('open', 'Open'), SxSegment('done', 'Answered')],
              value: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          ),
          const SizedBox(height: SxSpace.s12),
          Expanded(
            child: _tab == 'open'
                ? SxAsyncView<HomeData>(
                    value: value,
                    onRetry: () => invalidateHomeSources(container),
                    builder: (context, data) => _OpenList(data: data),
                  )
                : const _AnsweredList(),
          ),
        ],
      ),
    );
  }
}

class _OpenList extends StatelessWidget {
  const _OpenList({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    return SxScrollList(
      bottomInset: false,
      onRefresh: () => refreshHome(container),
      children: [
        HomeMargin(
          child: AnimatedSize(
            duration: SxMotion.base,
            curve: SxMotion.move,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.s8,
              children: [
                for (final (i, q) in data.openQuestions.indexed)
                  SxFadeUp(
                    key: ValueKey(q.id),
                    index: i,
                    child: QuestionCard(question: q, data: data, full: true),
                  ),
                if (data.openQuestions.isEmpty) const SxFadeUp(child: AllClearCard()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnsweredList extends ConsumerWidget {
  const _AnsweredList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeDataProvider).value;
    return SxAsyncView<List<Question>>(
      value: ref.watch(answeredQuestionsProvider),
      onRetry: () => ref.invalidate(answeredQuestionsProvider),
      isEmpty: (list) => list.isEmpty,
      empty: const SxEmptyState(
        icon: TablerIcons.message_circle_check,
        title: 'Nothing answered yet',
        body: 'Questions you answer show here.',
      ),
      builder: (context, list) => SxScrollList(
        bottomInset: false,
        onRefresh: () async {
          try {
            ref.invalidate(answeredQuestionsProvider);
            await ref.read(answeredQuestionsProvider.future);
          } on Object {
            // SxAsyncView reports a failed reload.
          }
        },
        children: [
          HomeMargin(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: SxSpace.s8,
              children: [
                for (final (i, q) in list.indexed)
                  SxFadeUp(
                    key: ValueKey(q.id),
                    index: i,
                    child: _AnsweredCard(question: q, data: data),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnsweredCard extends StatelessWidget {
  const _AnsweredCard({required this.question, required this.data});

  final Question question;
  final HomeData? data;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final name = data?.customerOf(question.conversationId) ?? 'Customer';
    final chat = data?.chatOf(question.conversationId);
    final when = question.answeredAt;
    // BACKEND GAP: answered questions don't say whether the answer was saved as a rule, so the
    // prototype's "Saved as rule" chip isn't shown.
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SxCustomerAvatar(name: name, channel: chat == null ? null : brandOfChannel(chat.channel)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                    ),
                    if (when != null)
                      Text(dayLabel(when), style: SxText.micro.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SxSpace.s12),
          Text('“${question.question}”', style: SxText.bodyS.copyWith(color: p.textPrimary)),
          const SizedBox(height: SxSpace.s8),
          SxAiNote('Your answer: ${question.answer ?? ''}', icon: TablerIcons.corner_down_right),
        ],
      ),
    );
  }
}
