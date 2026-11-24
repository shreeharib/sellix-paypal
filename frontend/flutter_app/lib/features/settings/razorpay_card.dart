/// The Razorpay card: connect the shop's own keys, then the webhook setup and status. Settings >
/// Payments and the onboarding pay step both show it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/api/sellix_api.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../design/design.dart';
import '../orders/order_actions.dart' show copyText;
import 'settings_providers.dart';

/// Razorpay's own sign-up page, opened in the phone's browser.
final razorpaySignUpUrl = Uri.parse('https://dashboard.razorpay.com/signup');

/// Opens a web page outside the app. Tests replace it.
@visibleForTesting
Future<bool> Function(Uri url) openExternal = (url) => launchUrl(url, mode: LaunchMode.externalApplication);

/// Key ids look like `rzp_test_...` or `rzp_live_...` (backend `payments/razorpay.py`).
final _keyIdPattern = RegExp(r'^rzp_(test|live)_[A-Za-z0-9]+$');

/// Reloads what depends on the account: the card itself, and `payments_ready` on the answers.
void _refreshAccount(ProviderContainer container) => container
  ..invalidate(paymentAccountProvider)
  ..invalidate(onboardingProvider);

class RazorpayCard extends ConsumerStatefulWidget {
  const RazorpayCard({super.key, required this.account, required this.owner, this.onConnected});

  final PaymentAccount account;

  /// Only the owner connects keys, sees the webhook secret, or changes anything.
  final bool owner;

  /// Called with the account the server returned after connecting.
  final ValueChanged<PaymentAccount>? onConnected;

  @override
  ConsumerState<RazorpayCard> createState() => _RazorpayCardState();
}

class _RazorpayCardState extends ConsumerState<RazorpayCard> {
  final _keyId = TextEditingController();
  final _keySecret = TextEditingController();
  String? _keyIdError;
  String? _secretError;

  /// The server's own words for a refused connect (422/502/403).
  String? _serverError;
  bool _busy = false;
  bool _showSecret = false;

  /// The webhook steps are optional, so they start folded away.
  bool _webhooksOpen = false;

  Future<void> _openSignUp() async {
    final opened = await openExternal(razorpaySignUpUrl);
    if (!opened && mounted) {
      showSxSnack(context, 'Could not open the browser. Go to dashboard.razorpay.com/signup.', sellix: false);
    }
  }

  @override
  void dispose() {
    _keyId.dispose();
    _keySecret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final keyId = _keyId.text.trim();
    final secret = _keySecret.text.trim();
    setState(() {
      _serverError = null;
      _keyIdError = keyId.isEmpty
          ? 'Paste your Key ID.'
          : (_keyIdPattern.hasMatch(keyId) ? null : 'A Key ID starts with rzp_test_ or rzp_live_.');
      _secretError = secret.isEmpty ? 'Paste your Key Secret.' : (secret.length > 128 ? 'That is too long for a Key Secret.' : null);
    });
    if (_keyIdError != null || _secretError != null) return;
    final container = containerOf(context);
    setState(() => _busy = true);
    try {
      final account = await container
          .read(sellixApiProvider)
          .connectPaymentAccount(keyId: keyId, keySecret: secret);
      _refreshAccount(container);
      if (!mounted) return;
      _keySecret.clear();
      setState(() => _busy = false);
      widget.onConnected?.call(account);
      showSxSnack(
        context,
        account.mode == 'live'
            ? 'Razorpay connected. Customers pay you on Razorpay now.'
            : 'Razorpay connected in test mode. No real money moves.',
        icon: TablerIcons.check,
        sellix: false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = error.message;
      });
    }
  }

  Future<void> _rotate() async {
    final yes = await showSxConfirm(
      context,
      title: 'Make a new webhook secret?',
      body:
          'The old secret stops working. Paste the new one into your Razorpay webhook, or webhooks '
          'fail until you do. Payments still confirm within a minute either way.',
      confirmLabel: 'New secret',
      confirmIcon: TablerIcons.refresh,
    );
    if (!yes || !mounted) return;
    await _run(
      (api) => api.rotateWebhookSecret(),
      'New webhook secret made. Paste it into Razorpay.',
      TablerIcons.refresh,
    );
  }

  Future<void> _disconnect() async {
    final upi = blankToNull(ref.read(onboardingProvider).value?.answers.upiId ?? '');
    final yes = await showSxConfirm(
      context,
      title: 'Disconnect Razorpay?',
      body: upi == null
          ? 'New payment links fall back to UPI, but you have no UPI ID saved. Add one below, or '
                'customers get no way to pay. You confirm UPI payments by hand.'
          : 'New payment links fall back to your UPI ID ($upi). You confirm those payments by hand '
                'when the money arrives.',
      confirmLabel: 'Disconnect',
      confirmIcon: TablerIcons.plug_connected_x,
    );
    if (!yes || !mounted) return;
    await _run(
      (api) async {
        await api.disconnectPaymentAccount();
        return null;
      },
      'Razorpay disconnected. New links use UPI.',
      TablerIcons.plug_connected_x,
    );
  }

  Future<void> _run(
    Future<PaymentAccount?> Function(SellixApi api) call,
    String done,
    IconData icon,
  ) async {
    final container = containerOf(context);
    setState(() => _busy = true);
    try {
      await call(container.read(sellixApiProvider));
      _refreshAccount(container);
      if (mounted) showSxSnack(context, done, icon: icon, sellix: false);
    } on ApiException catch (error) {
      if (mounted) showSxSnack(context, sxErrorMessage(error), icon: TablerIcons.alert_triangle, sellix: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return SxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          _head(context, account),
          if (account.isTestSetup) _testNote(context, account),
          if (account.connected) ..._connected(context, account) else ..._notConnected(context),
        ],
      ),
    );
  }

  Widget _head(BuildContext context, PaymentAccount account) {
    final p = context.sx;
    final chip = !account.connected
        ? const SxChip(label: 'Not connected')
        : account.mode == 'live'
        ? const SxChip(label: 'Live', tone: SxChipTone.positive, icon: TablerIcons.check)
        : const SxChip(label: 'Test mode', tone: SxChipTone.attention);
    return Row(
      spacing: SxSpace.s12,
      children: [
        const SxIconTile(icon: TablerIcons.credit_card),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Razorpay', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
              Text('UPI, cards and net banking', style: SxText.caption.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        chip,
      ],
    );
  }

  Widget _testNote(BuildContext context, PaymentAccount account) => SxBanner(
    tone: SxBannerTone.neutral,
    icon: TablerIcons.flask,
    message: account.source == PaymentSource.simulator
        ? 'This is a test setup. Payments go to a practice page and no real money moves.'
        : 'This is a test setup. Links come from sellix’s own test account, not yours.',
  );

  List<Widget> _notConnected(BuildContext context) {
    final p = context.sx;
    if (!widget.owner) {
      return [
        Text(
          'Only the shop’s owner can connect Razorpay.',
          style: SxText.caption.copyWith(color: p.textSecondary),
        ),
      ];
    }
    return [
      Text(
        'Customers pay on Razorpay’s page by UPI, card or net banking. The order is paid only when '
        'Razorpay says so. Setting it up takes about ten minutes.',
        style: SxText.bodyS.copyWith(color: p.textPrimary),
      ),
      const _Step(1, 'Create your free Razorpay account.'),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: SxSpace.s20),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SxButton(
            label: 'Open Razorpay sign-up',
            icon: TablerIcons.external_link,
            kind: SxButtonKind.secondary,
            onTap: _openSignUp,
          ),
        ),
      ),
      const _Step(
        2,
        'Razorpay asks for your business and bank details there. That is where your money is paid. '
        'Test mode works before that.',
      ),
      const _Step(3, 'In Razorpay, open Account & Settings, then API Keys, then Generate key.'),
      const _Step(4, 'Copy the Key ID and Key Secret into the boxes below.'),
      const SxAiNote(
        'sellix never sees your bank details. The money goes straight from Razorpay to your bank.',
        icon: TablerIcons.shield_lock,
      ),
      SxField(
        controller: _keyId,
        label: 'Key ID',
        hint: 'rzp_test_...',
        onTile: true,
        errorText: _keyIdError,
        maxLength: 64,
        enabled: !_busy,
        onChanged: (_) {
          if (_keyIdError != null || _serverError != null) {
            setState(() {
              _keyIdError = null;
              _serverError = null;
            });
          }
        },
      ),
      SxField(
        controller: _keySecret,
        label: 'Key Secret',
        hint: 'Paste the secret',
        onTile: true,
        obscureText: !_showSecret,
        errorText: _secretError,
        maxLength: 128,
        enabled: !_busy,
        trailing: SxIconButton(
          icon: _showSecret ? TablerIcons.eye_off : TablerIcons.eye,
          semanticLabel: _showSecret ? 'Hide the secret' : 'Show the secret',
          ghost: true,
          onTap: () => setState(() => _showSecret = !_showSecret),
        ),
        onChanged: (_) {
          if (_secretError != null || _serverError != null) {
            setState(() {
              _secretError = null;
              _serverError = null;
            });
          }
        },
      ),
      Text(
        'Test keys start with rzp_test_ and move no real money. Live keys start with rzp_live_.',
        style: SxText.caption.copyWith(color: p.textSecondary),
      ),
      if (_serverError != null)
        Semantics(
          liveRegion: true,
          child: Text(_serverError!, style: SxText.caption.copyWith(color: p.errorText)),
        ),
      SxButton(
        label: 'Connect Razorpay',
        icon: TablerIcons.plug_connected,
        fullWidth: true,
        loading: _busy,
        onTap: _busy ? null : _connect,
      ),
    ];
  }

  List<Widget> _connected(BuildContext context, PaymentAccount account) {
    final p = context.sx;
    final last = account.lastWebhookAt;
    final secret = account.webhookSecret;
    final url = account.webhookUrl;
    return [
      Column(
        children: [
          if (account.keyIdHint != null) SxKeyValue(label: 'Key ID', value: account.keyIdHint),
          if (account.connectedAt != null)
            SxKeyValue(label: 'Connected', value: formatDateTime(account.connectedAt!), divider: true),
        ],
      ),
      Row(
        spacing: SxSpace.s8,
        children: [
          Icon(
            last == null ? TablerIcons.clock : TablerIcons.circle_check,
            size: 20,
            color: last == null ? p.textSecondary : p.successText,
          ),
          Expanded(
            child: Text(
              last == null ? 'No webhook received yet' : 'Webhooks working, last at ${formatDateTime(last)}',
              style: SxText.bodyS.copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
      Divider(height: 1, thickness: 1, color: p.line),
      SxPressable(
        onTap: () => setState(() => _webhooksOpen = !_webhooksOpen),
        semanticLabel: _webhooksOpen ? 'Hide faster confirmations' : 'Show faster confirmations',
        child: Row(
          spacing: SxSpace.s8,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Faster confirmations (optional)', style: SxText.label.copyWith(color: p.textPrimary)),
                  Text(
                    'Optional: payments still confirm within a minute without it. With webhooks they '
                    'confirm in seconds.',
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(_webhooksOpen ? TablerIcons.chevron_up : TablerIcons.chevron_down, size: 20, color: p.textSecondary),
          ],
        ),
      ),
      if (_webhooksOpen) ...[
        const _Step(1, 'In Razorpay Dashboard, open Account & Settings, then Webhooks, then Add New Webhook.'),
        if (url != null) ...[
          const _Step(2, 'Paste this address as the Webhook URL.'),
          _CopyRow(value: url, what: 'Webhook address'),
        ],
        if (secret != null) ...[
          const _Step(3, 'Paste this as the Secret.'),
          _CopyRow(value: secret, what: 'Webhook secret'),
        ] else
          const _Step(3, 'Ask the shop’s owner for the secret.'),
        const _Step(4, 'Tick these events, then save.'),
        _CopyRow(
          value: account.webhookEvents.join('\n'),
          copyValue: account.webhookEvents.join(', '),
          what: 'Event list',
          mono: true,
        ),
        Text(
          'Test mode and live mode are set up separately in Razorpay. The same address and secret work '
          'for both.',
          style: SxText.caption.copyWith(color: p.textSecondary),
        ),
      ],
      if (widget.owner)
        SxButtonRow(
          children: [
            SxButton(
              label: 'New webhook secret',
              icon: TablerIcons.refresh,
              kind: SxButtonKind.secondary,
              onTap: _busy ? null : _rotate,
            ),
            SxButton(
              label: 'Disconnect',
              icon: TablerIcons.plug_connected_x,
              kind: SxButtonKind.secondary,
              onTap: _busy ? null : _disconnect,
            ),
          ],
        )
      else
        Text(
          'Only the shop’s owner can change this.',
          style: SxText.caption.copyWith(color: p.textSecondary),
        ),
    ];
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: SxSpace.s8,
      children: [
        Text('$number.', style: SxText.label.copyWith(color: p.textSecondary)),
        Expanded(child: Text(text, style: SxText.bodyS.copyWith(color: p.textPrimary))),
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.value, required this.what, this.copyValue, this.mono = false});

  final String value;
  final String? copyValue;
  final String what;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      padding: const EdgeInsets.fromLTRB(SxSpace.s12, SxSpace.s8, SxSpace.s4, SxSpace.s8),
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(SxRadius.tile)),
      child: Row(
        spacing: SxSpace.s8,
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: SxText.bodyS.copyWith(color: p.textPrimary, fontFamily: mono ? 'monospace' : null),
            ),
          ),
          SxIconButton(
            icon: TablerIcons.copy,
            semanticLabel: 'Copy ${what.toLowerCase()}',
            ghost: true,
            onTap: () => copyText(context, copyValue ?? value, what),
          ),
        ],
      ),
    );
  }
}
