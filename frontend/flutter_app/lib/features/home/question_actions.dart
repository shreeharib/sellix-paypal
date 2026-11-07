/// Answering and dismissing a needs-you question, from Home and the queue. Same path from both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../design/design.dart';
import '../chats/chats_providers.dart';
import '../orders/orders_providers.dart';
import '../stock/stock_providers.dart';
import 'home_providers.dart';

void _afterQuestionChange(ProviderContainer container) {
  container
    ..invalidate(openQuestionsProvider)
    ..invalidate(answeredQuestionsProvider)
    ..invalidate(closedQuestionsProvider)
    ..invalidate(conversationsProvider)
    ..invalidate(ordersProvider)
    ..invalidate(todayProvider);
}

/// sellix's first-person note on a question card, from what the API knows about the reply window.
// BACKEND GAP: questions have no reason, photo or sellix note, so the prototype's reason chip and
// note are built here from the reply window. The assistant's suggested answers are real.
String questionNote(Question question) {
  final closes = question.windowClosesAt;
  return switch (question.windowState) {
    'closing' when closes != null =>
      'I could not answer this, so I asked you. I can reply until ${formatTime(closes)}.',
    'human_agent_only' => 'The 24-hour reply window is over. Your answer may wait until they write again.',
    'closed' => 'The reply window has closed. They may not get your answer.',
    _ => 'I could not answer this, so I asked you.',
  };
}

String questionReason(Question question) => switch (question.windowState) {
  'closing' => 'Reply soon',
  'human_agent_only' || 'closed' => 'Window over',
  _ => 'Needs you',
};

String _deliveryText(String customer, String? delivery) => switch (delivery) {
  'sent' => 'Sent to $customer.',
  'human_agent' => 'Sent to $customer as you wrote it.',
  'pending_window' => 'Saved. $customer gets it when they write again.',
  'expired' => 'Saved, but $customer can no longer be reached on Instagram.',
  _ => 'Answer saved.',
};

/// Opens the answer sheet. Nothing is sent until the merchant taps "Send answer".
// BACKEND GAP: a sent answer can't be taken back, so the prototype's Undo isn't offered.
///
/// [initial] fills the answer, e.g. a suggested answer the merchant tapped; they can still edit it.
Future<void> answerQuestionFlow(
  BuildContext context,
  Question question,
  String customer, {
  bool aboveBar = true,
  String? initial,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final result = await showSxSheet<_Answered>(
    context,
    title: 'Answer $customer',
    builder: (sheet) => _AnswerSheet(
      question: question,
      initial: initial,
      onSend: (text, always) =>
          container.read(sellixApiProvider).answerQuestion(question.id, text, always: always),
      onStale: () => _afterQuestionChange(container),
    ),
  );
  if (result == null) return;
  _afterQuestionChange(container);
  if (!context.mounted) return;
  final sent = _deliveryText(customer, result.question.answerDelivery);
  showSxSnack(
    context,
    result.savedRule ? '$sent Rule saved. sellix will answer this alone.' : sent,
    icon: result.savedRule ? TablerIcons.bookmark : TablerIcons.send,
    aboveBar: aboveBar,
  );
}

/// Closes a question without answering, after asking.
Future<void> dismissQuestionFlow(
  BuildContext context,
  Question question,
  String customer, {
  bool aboveBar = true,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final sure = await showSxConfirm(
    context,
    title: 'Dismiss this question?',
    body: '$customer gets no answer from you. You can still reply in the chat.',
    confirmLabel: 'Dismiss',
  );
  if (!sure) return;
  try {
    await container.read(sellixApiProvider).closeQuestion(question.id);
  } catch (error) {
    if (context.mounted) showSxSnack(context, sxErrorMessage(error), aboveBar: aboveBar);
    _afterQuestionChange(container);
    return;
  }
  _afterQuestionChange(container);
  if (!context.mounted) return;
  showSxSnack(context, 'Question dismissed.', icon: TablerIcons.check, aboveBar: aboveBar);
}

class _Answered {
  const _Answered(this.question, this.savedRule);

  final Question question;
  final bool savedRule;
}

class _AnswerSheet extends StatefulWidget {
  const _AnswerSheet({
    required this.question,
    required this.onSend,
    required this.onStale,
    this.initial,
  });

  final Question question;
  final String? initial;
  final Future<Question> Function(String text, bool always) onSend;

  /// A refused answer usually means the question moved on elsewhere.
  final VoidCallback onStale;

  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  late final _text = TextEditingController(text: widget.initial);
  var _always = false;
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Type your answer first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final answered = await widget.onSend(text, _always);
      if (mounted) Navigator.of(context).pop(_Answered(answered, _always));
    } catch (error) {
      widget.onStale();
      if (mounted) {
        setState(() {
          _sending = false;
          _error = sxErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        Text('“${widget.question.question}”', style: SxText.bodyS.copyWith(color: p.textPrimary)),
        if (widget.question.suggestedAnswers.isNotEmpty)
          Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final suggestion in widget.question.suggestedAnswers)
                SxPickChip(
                  label: suggestion,
                  selected: _text.text.trim() == suggestion,
                  onTap: _sending
                      ? null
                      : () => setState(() {
                          _text.text = suggestion;
                          _text.selection = TextSelection.collapsed(offset: suggestion.length);
                          _error = null;
                        }),
                ),
            ],
          ),
        SxField(
          controller: _text,
          hint: 'Type your answer',
          maxLines: 3,
          minLines: 3,
          maxLength: 1000,
          errorText: _error,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          enabled: !_sending,
        ),
        Text(
          'Write in any language. sellix replies in the customer’s language.',
          style: SxText.caption.copyWith(color: p.textSecondary),
        ),
        SxSwitchRow(
          title: 'Save this as a rule?',
          subtitle: 'Next time, sellix answers on its own and does not ask you.',
          icon: TablerIcons.bookmark_plus,
          value: _always,
          onChanged: _sending ? null : (value) => setState(() => _always = value),
        ),
        SxButton(label: 'Send answer', fullWidth: true, loading: _sending, onTap: _sending ? null : _send),
      ],
    );
  }
}
