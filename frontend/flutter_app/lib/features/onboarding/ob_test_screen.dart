import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_common.dart';

/// The real assistant, through `/v1/simulator`: the same pipeline as Instagram, on a chat channel
/// that never leaves sellix. Replies are the model's, never canned. Empty until the merchant writes.
final _testChatProvider = FutureProvider.autoDispose<SimulatorChat>(
  (ref) => ref.watch(sellixApiProvider).simulatorChat(),
);

const _suggestions = ['Is it in stock today?', '20% discount?', 'Can I get it at 9 PM?', 'What are your hours?'];

class ObTestScreen extends ConsumerStatefulWidget {
  const ObTestScreen({super.key});

  @override
  ConsumerState<ObTestScreen> createState() => _ObTestScreenState();
}

class _ObTestScreenState extends ConsumerState<ObTestScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final Set<String> _used = {};
  SimulatorChat? _chat;
  String? _pending;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: SxMotion.slow, curve: SxMotion.curve);
      }
    });
  }

  Future<void> _send(String text, {String? quickReply, String? shown}) async {
    if (_pending != null) return;
    setState(() => _pending = shown ?? text);
    _toEnd();
    try {
      final chat = await ref.read(sellixApiProvider).simulatorSend(text: text, quickReply: quickReply);
      if (!mounted) return;
      setState(() {
        _chat = chat;
        _pending = null;
      });
      _toEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() => _pending = null);
      showSxSnack(context, sxErrorMessage(error));
    }
  }

  void _sendTyped() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    _send(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final loaded = ref.watch(_testChatProvider);
    final mq = MediaQuery.of(context);
    return SxScaffold(
      floating: SxBottomCta(label: 'Continue', onTap: () => context.push(Routes.obStock)),
      body: Column(
        children: [
          ObTop(step: 2, fraction: 0.9, fallback: Routes.obPay, onSkip: () => context.push(Routes.obStock)),
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s20, SxSpace.screen, SxSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Try your agent', style: SxText.titleL.copyWith(color: p.textPrimary)),
                const ObWhy('You are the customer. Nothing is sent to anyone. This test chat also shows in your Chats.'),
              ],
            ),
          ),
          Expanded(
            child: SxAsyncView<SimulatorChat>(
              value: _chat != null ? AsyncData(_chat!) : loaded,
              onRetry: () => ref.invalidate(_testChatProvider),
              loading: const SxSkeletonList(count: 3),
              builder: (context, chat) => _ChatList(
                chat: chat,
                pending: _pending,
                controller: _scroll,
                onButton: (b) => _send('', quickReply: b.payload, shown: b.title),
              ),
            ),
          ),
          if (loaded.hasValue) ...[
            SxFilterChips(
              children: [
                for (final s in _suggestions)
                  if (!_used.contains(s))
                    SxFilterChip(
                      label: s,
                      selected: false,
                      onTap: _pending != null
                          ? null
                          : () {
                              setState(() => _used.add(s));
                              _send(s);
                            },
                    ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SxSpace.s16, SxSpace.s8, SxSpace.s16, 0),
              child: SxComposer(
                controller: _text,
                hint: 'Write as a customer',
                sending: _pending != null,
                onSend: _sendTyped,
              ),
            ),
          ],
          // Room for the floating Continue button.
          SizedBox(height: SxSpace.s8 + 60 + SxSpace.navGap + mq.padding.bottom),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({required this.chat, required this.pending, required this.controller, required this.onButton});

  final SimulatorChat chat;
  final String? pending;
  final ScrollController controller;
  final ValueChanged<SimulatorButton> onButton;

  @override
  Widget build(BuildContext context) {
    final messages = chat.messages;
    final buttons = pending == null && messages.isNotEmpty && !messages.last.fromCustomer
        ? messages.last.buttons
        : const <SimulatorButton>[];
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s8, SxSpace.screen, SxSpace.s12),
      children: [
        const SxSystemEvent('Test chat', icon: TablerIcons.flask),
        const SizedBox(height: SxSpace.s8),
        for (final m in messages) ...[
          _TestBubble(text: m.body, fromCustomer: m.fromCustomer),
          const SizedBox(height: SxSpace.s8),
        ],
        if (pending != null) ...[
          _TestBubble(text: pending!, fromCustomer: true),
          const SizedBox(height: SxSpace.s8),
          const Align(alignment: AlignmentDirectional.centerEnd, child: SxTypingBubble()),
        ],
        if (buttons.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final b in buttons)
                SxButton(label: b.title, kind: SxButtonKind.secondary, onTap: () => onButton(b)),
            ],
          ),
      ],
    );
  }
}

class _TestBubble extends StatelessWidget {
  const _TestBubble({required this.text, required this.fromCustomer});

  final String text;
  final bool fromCustomer;

  @override
  Widget build(BuildContext context) {
    if (!fromCustomer) return SxBubble(text: text, sender: SxBubbleSender.sellix);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: SxSpace.s4, bottom: 2),
          child: Text('You, as customer', style: SxText.micro.copyWith(color: context.sx.textSecondary)),
        ),
        SxBubble(text: text, sender: SxBubbleSender.customer),
      ],
    );
  }
}
