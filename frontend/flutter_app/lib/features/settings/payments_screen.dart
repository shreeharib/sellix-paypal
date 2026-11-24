import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/router.dart';
import '../../design/design.dart';
import 'razorpay_card.dart';
import 'settings_providers.dart';

/// `payment_hold_minutes` in the backend's config.
const _holdMinutes = 15;

/// The same rule as onboarding's UPI step.
final _upiPattern = RegExp(r'^[\w.-]{2,}@[a-z0-9.-]{2,}$', caseSensitive: false);

/// Razorpay first; the UPI ID is the fallback when Razorpay isn't connected.
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

  void _retry() {
    ref
      ..invalidate(onboardingProvider)
      ..invalidate(paymentAccountProvider)
      ..invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final account = ref.watch(paymentAccountProvider);
    final data = onboarding.value;
    if (data != null) _upi ??= TextEditingController(text: data.answers.upiId ?? '');
    // Both must load: the UPI card's wording depends on whether Razorpay is connected.
    final o = onboarding.value;
    final a = account.value;
    final failed = onboarding.hasError ? onboarding : (account.hasError ? account : null);
    final AsyncValue<(Onboarding, PaymentAccount)> both = o != null && a != null
        ? AsyncData((o, a))
        : failed != null
        ? AsyncError(failed.error!, failed.stackTrace ?? StackTrace.current)
        : const AsyncLoading();
    return SxScaffold(
      floating: data == null
          ? null
          : SxBottomCta(
              label: _done ? 'Saved' : 'Save UPI ID',
              icon: TablerIcons.check,
              loading: _saving,
              done: _done,
              onTap: _done ? null : () => _save(data),
            ),
      body: Column(
        children: [
          const SxDetailHeader(title: 'Payments', meta: 'How customers pay you', fallback: Routes.profile),
          Expanded(
            child: SxAsyncView<(Onboarding, PaymentAccount)>(
              value: both,
              onRetry: _retry,
              loading: const SxSkeletonList(count: 4, itemHeight: 120),
              builder: (context, loaded) => _list(context, loaded.$1, loaded.$2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, Onboarding data, PaymentAccount account) {
    final p = context.sx;
    // Staff see the account, but only the owner changes it. Until `me` loads, nothing is offered.
    final owner = ref.watch(meProvider).value?.isOwner ?? false;
    Widget titles(String title, String subtitle) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
        Text(subtitle, style: SxText.caption.copyWith(color: p.textSecondary)),
      ],
    );
    return SxScrollList(
      onRefresh: () async {
        _retry();
        await ref.read(paymentAccountProvider.future);
      },
      children: [
        Mx(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: SxSpace.s8,
            children: [
              SxFadeUp(child: RazorpayCard(account: account, owner: owner)),
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
                          Expanded(child: titles('UPI ID', 'When Razorpay isn’t connected')),
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
                      Text(
                        account.connected
                            ? 'Used only if you disconnect Razorpay. Then customers pay this UPI ID, '
                                  'and you confirm each payment by hand when the money arrives.'
                            : 'Used while Razorpay isn’t connected. Customers pay this UPI ID, and you '
                                  'confirm each payment by hand when the money arrives. sellix can’t see UPI payments.',
                        style: SxText.caption.copyWith(color: p.textSecondary),
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
