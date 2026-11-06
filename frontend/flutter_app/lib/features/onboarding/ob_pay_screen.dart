import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'ob_answers_text.dart';
import 'ob_common.dart';

class ObPayScreen extends ConsumerStatefulWidget {
  const ObPayScreen({super.key});

  @override
  ConsumerState<ObPayScreen> createState() => _ObPayScreenState();
}

class _ObPayScreenState extends ConsumerState<ObPayScreen> with ObSaving {
  final _upi = TextEditingController();
  bool _ready = false;
  String? _error;

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  void _load() {
    final draft = ref.watch(onboardingDraftProvider).value;
    if (_ready || draft == null) return;
    _ready = true;
    _upi.text = draft.answers.upiId ?? '';
  }

  void _continue() {
    final v = _upi.text.trim();
    if (!obUpiPattern.hasMatch(v)) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = v.isEmpty
            ? 'Enter your UPI ID, like name@bank. To add it later, tap Skip.'
            : 'That is not a UPI ID. It looks like name@bank.';
      });
      return;
    }
    saveThen((a) => a.copyWith(upiId: v), () => context.push(Routes.obTest));
  }

  @override
  Widget build(BuildContext context) {
    _load();
    final p = context.sx;
    final draft = ref.watch(onboardingDraftProvider).value;
    final paypalReady = draft?.paymentsReady ?? false;
    final whatsappOn = draft?.channels.any((c) => c.channel == 'whatsapp' && c.status == 'active') ?? false;
    return ObStepFrame(
      step: 2,
      fraction: 0.5,
      fallback: Routes.obHours,
      title: 'How do customers pay?',
      why: 'sellix sends the right payment option and marks the order paid.',
      saving: saving,
      onContinue: _ready ? _continue : null,
      onSkip: () => context.push(Routes.obTest),
      children: [
        const SizedBox(height: SxSpace.s20),
        SxFadeUp(
          index: 2,
          child: SxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SxIconTile(child: SxBrandIcon(SxBrand.paypal)),
                    const SizedBox(width: SxSpace.s12),
                    Expanded(child: _Titled('PayPal', 'For customers abroad')),
                    paypalReady
                        ? const SxChip(label: 'Ready', tone: SxChipTone.positive, icon: TablerIcons.check)
                        : const SxChip(label: 'Not set up yet'),
                  ],
                ),
                const SizedBox(height: SxSpace.s12),
                const SxAiNote('I send a payment link. The order is paid only when PayPal confirms. A screenshot never counts.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: SxSpace.s8),
        SxFadeUp(
          index: 3,
          child: SxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SxIconTile(child: SxBrandIcon(SxBrand.upi)),
                    const SizedBox(width: SxSpace.s12),
                    Expanded(child: _Titled('UPI', 'For customers in India')),
                  ],
                ),
                const SizedBox(height: SxSpace.s12),
                SxField(
                  controller: _upi,
                  onTile: true,
                  hint: 'yourname@bank',
                  maxLength: 200,
                  errorText: _error,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: SxSpace.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SxSpace.s4),
                  child: Text(
                    'Your own UPI ID, from your bank or UPI app. You confirm payments in one tap when the money arrives.',
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('Add WhatsApp', style: SxText.titleM.copyWith(color: p.textPrimary)),
        const SizedBox(height: SxSpace.s12),
        SxFadeUp(
          index: 4,
          child: SxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SxIconTile(child: SxBrandIcon(SxBrand.whatsapp)),
                    const SizedBox(width: SxSpace.s12),
                    Expanded(child: _Titled('WhatsApp Business', 'Many of your customers message here. One inbox for both.')),
                    if (whatsappOn)
                      const SxChip(label: 'Connected', tone: SxChipTone.positive, icon: TablerIcons.check),
                  ],
                ),
                if (!whatsappOn) ...[
                  const SizedBox(height: SxSpace.s12),
                  // BACKEND GAP: no endpoint connects WhatsApp Business.
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SxButton(label: 'Connect WhatsApp', kind: SxButtonKind.secondary, onTap: null),
                  ),
                  const SizedBox(height: SxSpace.s8),
                  Text(
                    'WhatsApp is not available yet. sellix answers Instagram for now.',
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Titled extends StatelessWidget {
  const _Titled(this.title, this.meta);

  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
        Text(meta, style: SxText.caption.copyWith(color: p.textSecondary)),
      ],
    );
  }
}
