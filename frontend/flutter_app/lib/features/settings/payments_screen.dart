import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'settings_providers.dart';

/// PayPal's currencies on the backend (`modules/payments/paypal.py`). The API does not list them.
const _payPalCurrencies = ['USD', 'SGD', 'GBP', 'EUR', 'AUD', 'CAD', 'NZD'];

/// `payment_hold_minutes` in the backend's config.
const _holdMinutes = 15;

/// The same rule as onboarding's UPI step.
final _upiPattern = RegExp(r'^[\w.-]{2,}@[a-z0-9.-]{2,}$', caseSensitive: false);

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  TextEditingController? _upi;
  String? _error;
  bool _saving = false;
  bool _done = false;

  @override
  void dispose() {
    _upi?.dispose();
    super.dispose();
  }

  Future<void> _save(Onboarding loaded) async {
    final text = _upi!.text.trim();
    if (text.isNotEmpty && !_upiPattern.hasMatch(text)) {
      setState(() => _error = 'Check the UPI ID. It looks like yourname@bank.');
      return;
    }
    if (text == (loaded.answers.upiId ?? '')) {
      await finishSave(context, null, fallback: Routes.profile);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await saveAnswers(containerOf(context), (a) => a.copyWith(upiId: blankToNull(text)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSxSnack(context, sxErrorMessage(error));
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _done = true;
    });
    await finishSave(context, 'Payment settings saved.', fallback: Routes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final data = onboarding.value;
    if (data != null) _upi ??= TextEditingController(text: data.answers.upiId ?? '');
    return SxScaffold(
      floating: data == null
          ? null
          : SxBottomCta(
              label: _done ? 'Saved' : 'Save',
              icon: TablerIcons.check,
              loading: _saving,
              done: _done,
              onTap: _done ? null : () => _save(data),
            ),
      body: Column(
        children: [
          const SxDetailHeader(title: 'Payments', meta: 'How customers pay you', fallback: Routes.profile),
          Expanded(
            child: SxAsyncView<Onboarding>(
              value: onboarding,
              onRetry: () => ref.invalidate(onboardingProvider),
              loading: const SxSkeletonList(count: 4, itemHeight: 120),
              builder: (context, data) => _list(context, data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, Onboarding data) {
    final p = context.sx;
    Widget titles(String title, String subtitle) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
        Text(subtitle, style: SxText.caption.copyWith(color: p.textSecondary)),
      ],
    );
    return SxScrollList(
      children: [
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              SxFadeUp(
                child: SxCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: SxSpace.s12,
                    children: [
                      Row(
                        spacing: SxSpace.s12,
                        children: [
                          const SxIconTile(child: SxBrandIcon(SxBrand.paypal)),
                          Expanded(child: titles('PayPal', 'For customers abroad')),
                          if (data.paymentsReady)
                            const SxChip(label: 'Ready', tone: SxChipTone.positive, icon: TablerIcons.check)
                          else
                            const SxChip(label: 'Not ready'),
                        ],
                      ),
                      Wrap(
                        spacing: SxSpace.s4,
                        runSpacing: SxSpace.s4,
                        children: [for (final c in _payPalCurrencies) SxChip(label: c)],
                      ),
                      const SxAiNote('An order is paid only when PayPal confirms. A screenshot never counts.'),
                    ],
                  ),
                ),
              ),
              SxFadeUp(
                index: 1,
                child: SxCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: SxSpace.s12,
                    children: [
                      Row(
                        spacing: SxSpace.s12,
                        children: [
                          const SxIconTile(child: SxBrandIcon(SxBrand.upi)),
                          Expanded(child: titles('UPI', 'For customers in India')),
                        ],
                      ),
                      SxField(
                        controller: _upi,
                        hint: 'yourname@bank',
                        onTile: true,
                        errorText: _error,
                        maxLength: answerShortLimit,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                      Row(
                        spacing: SxSpace.s12,
                        children: [
                          Expanded(child: titles('You confirm each payment', 'sellix cannot see UPI payments')),
                          // Fixed on: with no way to see UPI money, a merchant confirmation is the only path.
                          const SxToggle(
                            value: true,
                            onChanged: null,
                            semanticLabel: 'You confirm each UPI payment',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SxFadeUp(
                index: 2,
                child: SxCard(
                  child: Row(
                    spacing: SxSpace.s12,
                    children: [
                      Expanded(
                        child: titles(
                          'Hold stock while unpaid',
                          'Minutes, then stock goes back. Changing this is not available yet.',
                        ),
                      ),
                      // BACKEND GAP: the hold time is server config with no endpoint, so this cannot change.
                      const SxStepper(value: _holdMinutes, onChanged: null, itemName: 'hold minutes'),
                    ],
                  ),
                ),
              ),
              SxFadeUp(
                index: 3,
                child: SxCard(
                  child: Row(
                    spacing: SxSpace.s12,
                    children: [
                      const SxIconTile(icon: TablerIcons.cash),
                      Expanded(child: titles('Cash on delivery', 'Not available yet')),
                      const SxChip(label: 'Off'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
