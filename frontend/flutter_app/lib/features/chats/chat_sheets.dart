import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../design/design.dart';
import 'chat_labels.dart';

/// What the merchant wrote in the answer sheet.
class AnswerDraft {
  const AnswerDraft(this.text, {required this.always});

  final String text;

  /// sellix gives this answer to the same question from now on.
  final bool always;
}

/// "Write my own reply". Null when dismissed.
Future<AnswerDraft?> showAnswerSheet(BuildContext context, String question) =>
    showSxSheet<AnswerDraft>(
      context,
      title: 'Write my own reply',
      subtitle: question,
      builder: (_) => const _AnswerSheet(),
    );

class _AnswerSheet extends StatefulWidget {
  const _AnswerSheet();

  @override
  State<_AnswerSheet> createState() => _AnswerSheetState();
}

class _AnswerSheetState extends State<_AnswerSheet> {
  final _text = TextEditingController();
  String? _error;
  bool _always = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Type a reply first');
      return;
    }
    Navigator.of(context).pop(AnswerDraft(text, always: _always));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: SxSpace.s12,
    children: [
      SxField(
        controller: _text,
        hint: 'Your reply',
        errorText: _error,
        maxLines: 4,
        maxLength: 1000,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      SxSwitchRow(
        title: 'Save this as a rule?',
        subtitle: 'Next time, sellix answers on its own and does not ask you.',
        icon: TablerIcons.bookmark_plus,
        value: _always,
        onChanged: (value) => setState(() => _always = value),
      ),
      SxButton(label: 'Send', icon: TablerIcons.send, fullWidth: true, onTap: _send),
    ],
  );
}

enum ChatMenuChoice { customer, order, inbox }

/// The chat menu, the prototype's `chatMenu`. Spend comes from the orders the API returns.
Future<ChatMenuChoice?> showChatMenu(
  BuildContext context, {
  required Conversation chat,
  required List<Order> orders,
  required Order? order,
}) {
  final paid = orders.where((o) => o.paymentStatus == 'paid').toList();
  final spent = <String, int>{};
  for (final o in paid) {
    spent[o.currency] = (spent[o.currency] ?? 0) + o.totalMinor;
  }
  final total = [for (final e in spent.entries) money(e.value, e.key)].join(' + ');
  final channel = channelName(chat.channel);
  final isInstagram = chat.channel == 'instagram';
  return showSxSheet<ChatMenuChoice>(
    context,
    builder: (sheet) {
      final p = sheet.sx;
      void pick(ChatMenuChoice choice) => Navigator.of(sheet).pop(choice);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s16,
        children: [
          Row(
            spacing: SxSpace.s12,
            children: [
              SxCustomerAvatar(
                name: chat.customerHandle,
                large: true,
                channel: channelBrand(chat.channel),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chat.customerHandle, style: SxText.titleM.copyWith(color: p.textPrimary)),
                    Text(
                      '${paid.length} paid order${paid.length == 1 ? '' : 's'}'
                      '${paid.isEmpty ? '' : ' · $total spent'}',
                      style: SxText.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SxGroup(
            children: [
              SxListRow(
                title: 'View customer',
                icon: TablerIcons.user,
                onTap: () => pick(ChatMenuChoice.customer),
              ),
              if (order != null)
                SxListRow(
                  title: 'Order #${order.number}',
                  icon: TablerIcons.receipt,
                  onTap: () => pick(ChatMenuChoice.order),
                ),
              // BACKEND GAP: no endpoint creates an order or sends a payment link from the app.
              const SxListRow(
                title: 'Create an order',
                subtitle: 'Not available yet. sellix takes orders in the chat.',
                icon: TablerIcons.receipt_2,
              ),
              // BACKEND GAP: conversations carry no link to the thread, so this opens the inbox.
              SxListRow(
                title: 'Open in $channel',
                subtitle: isInstagram
                    ? 'Opens your inbox, not this chat.'
                    : 'Not available yet. Open $channel and find this chat.',
                leading: channelBrand(chat.channel) == null
                    ? null
                    : SxBrandIcon(channelBrand(chat.channel)!),
                icon: TablerIcons.external_link,
                onTap: isInstagram ? () => pick(ChatMenuChoice.inbox) : null,
              ),
            ],
          ),
        ],
      );
    },
  );
}
