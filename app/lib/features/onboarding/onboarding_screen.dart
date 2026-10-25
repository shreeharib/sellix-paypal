import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../settings/settings_screen.dart';
import 'onboarding_providers.dart';

final onboardingProvider = FutureProvider.autoDispose<Onboarding>(
  (ref) => ref.watch(sellixApiProvider).onboarding(),
);

/// Answer keys with a text field, as in backend/app/modules/shop_profile/schemas.py.
const _textKeys = [
  'category', 'area', 'city', 'address', 'hours', 'weekly_off', 'products', //
  'intro', 'address_customers', 'fulfilment', 'custom_orders', 'cancellations',
  'never_promise', 'faqs',
];

const _stepCount = 6;

/// The guided setup after the first "Continue with Instagram": confirms the account is
/// connected, then asks about the shop. Every step can be skipped and finished in Settings.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _shopName = TextEditingController();
  final _text = {for (final key in _textKeys) key: TextEditingController()};
  String? _tone;
  bool? _emoji;
  bool _loaded = false;
  bool _saving = false;
  int _step = 0;

  @override
  void dispose() {
    _shopName.dispose();
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(Onboarding data) {
    _shopName.text = data.shopName;
    for (final key in _textKeys) {
      _text[key]!.text = data.answers.text(key);
    }
    _tone = data.answers.values['tone'] as String? ?? 'friendly'; // the plan's defaults
    _emoji = data.answers.values['emoji'] as bool? ?? true;
    _loaded = true;
  }

  OnboardingAnswers get _answers => OnboardingAnswers({
        for (final key in _textKeys)
          if (_text[key]!.text.trim().isNotEmpty) key: _text[key]!.text.trim(),
        'tone': ?_tone,
        'emoji': ?_emoji,
      });

  /// Saves what's been answered so far; `complete` finishes the setup.
  Future<bool> _save({bool complete = false}) async {
    final name = _shopName.text.trim();
    if (name.isEmpty) {
      setState(() => _step = 1);
      showMessage(context, context.l10n.onboardingNameRequired);
      return false;
    }
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).saveOnboarding(
            shopName: name,
            answers: _answers,
            complete: complete,
          );
      return true;
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _next() async {
    if (_step > 0 && !await _save()) return;
    if (_step < _stepCount - 1) {
      setState(() => _step++);
    } else {
      await _finish();
    }
  }

  void _skip() => setState(() => _step++);

  Future<void> _finish() async {
    if (!await _save(complete: true)) return;
    ref.invalidate(meProvider);
    ref.read(onboardingStatusProvider.notifier).completed(); // the router moves on to Today
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onboarding = ref.watch(onboardingProvider);
    if (!_loaded && onboarding.hasValue) _load(onboarding.value!);
    final last = _step == _stepCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.onboardingStep(_step + 1, _stepCount)),
        actions: [
          TextButton(
            onPressed: _saving || !onboarding.hasValue ? null : _finish,
            child: Text(l10n.onboardingFinishLater),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_step + 1) / _stepCount),
        ),
      ),
      body: AsyncView(
        value: onboarding,
        onRetry: () => ref.invalidate(onboardingProvider),
        data: (data) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(Insets.md),
            children: switch (_step) {
              0 => _connected(data),
              1 => _shop(),
              2 => _products(),
              3 => _persona(),
              4 => _policies(),
              _ => _payments(data),
            },
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: _saving ? null : () => setState(() => _step--),
                  child: Text(l10n.onboardingBack),
                ),
              const Spacer(),
              if (_step > 1 && !last)
                TextButton(onPressed: _saving ? null : _skip, child: Text(l10n.onboardingSkip)),
              const SizedBox(width: Insets.sm),
              FilledButton(
                onPressed: _saving || !onboarding.hasValue ? null : _next,
                child: Text(last ? l10n.onboardingFinish : l10n.onboardingNext),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _connected(Onboarding data) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final instagram = [for (final c in data.channels) if (c.channel == 'instagram') c];
    final active = instagram.where((c) => c.status == 'active').firstOrNull;
    return [
      _Heading(
        title: active != null ? l10n.onboardingConnectedTitle : l10n.onboardingNotConnectedTitle,
        body: active != null ? l10n.onboardingConnectedBody : l10n.onboardingNotConnectedBody,
      ),
      if (active != null)
        Card(
          child: ListTile(
            leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
            title: Text(l10n.settingsInstagram(active.username ?? '')),
            subtitle: Text(l10n.onboardingReceivingMessages),
          ),
        ),
    ];
  }

  List<Widget> _shop() {
    final l10n = context.l10n;
    return [
      _Heading(title: l10n.onboardingShopTitle, body: l10n.onboardingShopBody),
      _field(null, l10n.settingsShopName, controller: _shopName),
      _field('category', l10n.onboardingCategory, hint: l10n.onboardingCategoryHint),
      _field('area', l10n.onboardingArea),
      _field('city', l10n.onboardingCity),
      _field('address', l10n.onboardingAddress, lines: 2),
      _field('hours', l10n.onboardingHours, hint: l10n.onboardingHoursHint),
      _field('weekly_off', l10n.onboardingWeeklyOff, hint: l10n.onboardingWeeklyOffHint),
    ];
  }

  List<Widget> _products() {
    final l10n = context.l10n;
    return [
      _Heading(title: l10n.onboardingProductsTitle, body: l10n.onboardingProductsBody),
      _field('products', l10n.onboardingProducts, hint: l10n.onboardingProductsHint, lines: 3),
    ];
  }

  List<Widget> _persona() {
    final l10n = context.l10n;
    return [
      _Heading(title: l10n.onboardingPersonaTitle, body: l10n.onboardingPersonaBody),
      _field('intro', l10n.onboardingIntro, hint: l10n.onboardingIntroHint),
      Text(l10n.onboardingTone, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: Insets.sm),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'friendly', label: Text(l10n.onboardingToneFriendly)),
          ButtonSegment(value: 'formal', label: Text(l10n.onboardingToneFormal)),
        ],
        selected: {?_tone},
        emptySelectionAllowed: true,
        onSelectionChanged: (selected) => setState(() => _tone = selected.firstOrNull),
      ),
      const SizedBox(height: Insets.sm),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.onboardingEmoji),
        value: _emoji ?? true,
        onChanged: (value) => setState(() => _emoji = value),
      ),
      _field(
        'address_customers',
        l10n.onboardingAddressCustomers,
        hint: l10n.onboardingAddressCustomersHint,
      ),
    ];
  }

  List<Widget> _policies() {
    final l10n = context.l10n;
    return [
      _Heading(title: l10n.onboardingPoliciesTitle, body: l10n.onboardingPoliciesBody),
      _field('fulfilment', l10n.onboardingFulfilment, hint: l10n.onboardingFulfilmentHint, lines: 2),
      _field(
        'custom_orders',
        l10n.onboardingCustomOrders,
        hint: l10n.onboardingCustomOrdersHint,
        lines: 2,
      ),
      _field('cancellations', l10n.onboardingCancellations, lines: 2),
      _field(
        'never_promise',
        l10n.onboardingNeverPromise,
        hint: l10n.onboardingNeverPromiseHint,
        lines: 2,
      ),
      _field('faqs', l10n.onboardingFaqs, hint: l10n.onboardingFaqsHint, lines: 4),
    ];
  }

  List<Widget> _payments(Onboarding data) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return [
      _Heading(title: l10n.onboardingPaymentsTitle, body: l10n.onboardingPaymentsBody),
      Card(
        child: ListTile(
          leading: Icon(
            data.paymentsReady ? Icons.check_circle : Icons.schedule,
            color: data.paymentsReady ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          title: Text(l10n.onboardingPayPal),
          subtitle: Text(
            data.paymentsReady ? l10n.onboardingPaymentsReady : l10n.onboardingPaymentsNotReady,
          ),
        ),
      ),
    ];
  }

  Widget _field(
    String? key,
    String label, {
    String? hint,
    int lines = 1,
    TextEditingController? controller,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Insets.md),
        child: TextField(
          controller: controller ?? _text[key]!,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 3,
          textInputAction: lines == 1 ? TextInputAction.next : TextInputAction.newline,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Insets.sm),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
