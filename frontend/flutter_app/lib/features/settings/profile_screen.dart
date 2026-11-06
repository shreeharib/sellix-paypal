import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme_mode.dart';
import '../../design/design.dart';
import '../orders/orders_providers.dart';
import '../stock/stock_providers.dart';
import 'automations_store.dart';
import 'hours_codec.dart';
import 'saved_rules.dart';
import 'settings_providers.dart';
import 'shop_type.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// What the switch shows while the server has not answered.
  bool? _agentPending;

  /// The rows' values come from these too; a failed one would otherwise stay blank after a retry.
  void _invalidateAll() => ref
    ..invalidate(onboardingProvider)
    ..invalidate(shopProfileProvider)
    ..invalidate(ordersProvider)
    ..invalidate(meProvider);

  Future<void> _refresh() async {
    _invalidateAll();
    await ref.read(meProvider.future);
  }

  Future<void> _setAgent(bool on) async {
    setState(() => _agentPending = on);
    try {
      await ref.read(sellixApiProvider).updateMerchant(agentEnabled: on);
      ref
        ..invalidate(todayProvider)
        ..invalidate(meProvider);
      await ref.read(meProvider.future);
      if (!mounted) return;
      showSxSnack(
        context,
        on ? 'sellix is live again.' : 'sellix is paused. Messages are saved.',
        icon: on ? TablerIcons.check : TablerIcons.player_pause,
      );
    } on ApiException catch (error) {
      if (mounted) showSxSnack(context, sxErrorMessage(error));
    } finally {
      if (mounted) setState(() => _agentPending = null);
    }
  }

  Future<void> _signOut() async {
    final yes = await showSxConfirm(
      context,
      title: 'Sign out?',
      body: 'sellix keeps answering your customers. You stop getting notifications on this phone.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Stay',
    );
    if (!yes) return;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  LocalAlerts _alerts(String merchantId) {
    final prefs = ref.read(sharedPreferencesProvider);
    return LocalAlerts(prefs.getString, prefs.setString, merchantId);
  }

  Future<void> _pickMorning(LocalAlerts alerts) async {
    final time = await showTimeSheet(
      context,
      title: 'Morning reminder',
      current: alerts.morning,
      note: const SxLocalOnlyNote(),
    );
    if (time == null) return;
    await alerts.setMorning(time);
    if (mounted) setState(() {});
  }

  Future<void> _pickQuiet(LocalAlerts alerts) async {
    final picked = await showSxSheet<(String, String)>(
      context,
      title: 'Quiet hours',
      subtitle: 'You get no notifications between these times.',
      builder: (_) => _QuietSheet(from: alerts.quietFrom, to: alerts.quietTo),
    );
    if (picked == null) return;
    await alerts.setQuiet(picked.$1, picked.$2);
    if (mounted) setState(() {});
  }

  void _pickLanguage() {
    showSxSheet<void>(
      context,
      title: 'App language',
      subtitle: 'Customers still get replies in their own language.',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s8,
        children: [
          SxChoiceCard(
            title: 'English',
            check: true,
            selected: true,
            onTap: () => Navigator.of(sheet).pop(),
          ),
          // Shared gap: the app has no translations or locale setting yet, so a pick would change nothing.
          for (final (label, name) in const [('தமிழ் (Tamil)', 'Tamil'), ('हिन्दी (Hindi)', 'Hindi')])
            SxChoiceCard(
              title: label,
              subtitle: 'Coming soon',
              check: true,
              onTap: () => showSxSnack(context, '$name is coming soon.', icon: TablerIcons.clock),
            ),
        ],
      ),
    );
  }

  void _openHelp() {
    showSxSheet<void>(
      context,
      title: 'Help and how-tos',
      subtitle: 'Start here. Written guides and chat with a person are coming later.',
      builder: (sheet) {
        void leave(void Function() go) {
          Navigator.of(sheet).pop();
          go();
        }

        return SxGroup(
          children: [
            SxListRow(
              icon: TablerIcons.microphone,
              title: 'Set today’s stock',
              subtitle: 'Say it, type it or use a photo',
              onTap: () => leave(() => context.push(Routes.morning)),
            ),
            SxListRow(
              icon: TablerIcons.hand_stop,
              title: 'Answer what sellix asks',
              subtitle: 'Questions wait in Needs you',
              onTap: () => leave(() => context.push(Routes.needs)),
            ),
            SxListRow(
              icon: TablerIcons.receipt,
              title: 'Move an order along',
              subtitle: 'Each order shows its next step',
              onTap: () => leave(() => context.go(Routes.orders)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return SxScaffold(
      body: SxAsyncView<Me>(
        value: me,
        onRetry: _invalidateAll,
        loading: const SxSkeletonList(topHeight: 160),
        builder: (context, data) => _body(context, data),
      ),
    );
  }

  Widget _body(BuildContext context, Me me) {
    final p = context.sx;
    final onboarding = ref.watch(onboardingProvider).value;
    final profile = ref.watch(shopProfileProvider);
    final automations = ref.watch(automationsProvider).value;
    final orders = ref.watch(ordersProvider).value;
    final alerts = _alerts(me.merchant.id);
    final themeMode = ref.watch(themeModeProvider);

    final instagram = channelOf(me.channels, 'instagram');
    final whatsapp = channelOf(me.channels, 'whatsapp');
    final handle = instagram?.username;
    final agentOn = _agentPending ?? me.merchant.agentEnabled;

    final now = DateTime.now();
    final monthOrders = orders?.where((o) {
      final at = o.createdAt.toLocal();
      return at.year == now.year && at.month == now.month;
    }).length;

    final paymentNames = [
      if (onboarding?.paymentsReady ?? false) 'PayPal',
      if (blankToNull(onboarding?.answers.upiId ?? '') != null) 'UPI',
    ];
    final knowsValue = profile.value == null
        ? null
        : updatedWords(profile.value!.createdAt).replaceFirst('updated', 'Updated');

    return SxScrollList(
      onRefresh: _refresh,
      children: [
        const SizedBox(height: SxSpace.s12),
        const SxPageTitle(title: 'Profile'),
        const SizedBox(height: SxSpace.s16),
        Mx(
          child: SxFadeUp(
            child: SxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    spacing: SxSpace.s12,
                    children: [
                      SxInitialsAvatar(name: me.merchant.name, size: 56),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(me.merchant.name, style: SxText.titleM.copyWith(color: p.textPrimary)),
                            if (handle != null)
                              Text('@$handle', style: SxText.caption.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ),
                      SxIconButton(
                        icon: TablerIcons.pencil,
                        semanticLabel: 'Edit shop',
                        onTap: () => context.push(Routes.shopprofile),
                      ),
                    ],
                  ),
                  const SizedBox(height: SxSpace.s12),
                  Divider(height: 1, thickness: 1, color: p.line),
                  SxPressable(
                    onTap: onboarding == null ? null : () => changeShopType(context, onboarding.answers.category),
                    semanticLabel: 'Shop type: ${categoryLabel(onboarding?.answers.category)}. Change it',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: SxSpace.s12),
                      child: Row(
                        spacing: SxSpace.s12,
                        children: [
                          SxIconTile(icon: categoryOf(onboarding?.answers.category).icon, size: 36),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Shop type', style: SxText.caption.copyWith(color: p.textSecondary)),
                                Text(
                                  onboarding == null ? ' ' : categoryLabel(onboarding.answers.category),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SxText.bodyStrong.copyWith(color: p.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          Icon(TablerIcons.chevron_right, size: 20, color: p.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, thickness: 1, color: p.line),
                  const SizedBox(height: SxSpace.s12),
                  // BACKEND GAP: no plan or billing on the API, so the prototype's "Free plan" label is
                  // not shown. The count is from the latest orders only: the API has no month filter.
                  Row(
                    children: [
                      Expanded(child: Text('This month', style: SxText.label.copyWith(color: p.textPrimary))),
                      Text(
                        monthOrders == null
                            ? ' '
                            : '${monthOrders >= ordersWindow ? '$ordersWindow+' : monthOrders} '
                                  'order${monthOrders == 1 ? '' : 's'}',
                        style: SxText.caption.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SettingsGroupLabel('sellix'),
        Mx(
          child: SxFadeUp(
            index: 1,
            child: SxGroup(
              children: [
                SxSwitchRow(
                  icon: TablerIcons.sparkles,
                  title: 'Agent replies to customers',
                  subtitle: agentOn ? 'Replying to your DMs' : 'Off: messages are saved, nobody replies',
                  value: agentOn,
                  signal: true,
                  onChanged: _agentPending == null ? _setAgent : null,
                ),
                SxListRow(
                  icon: TablerIcons.bolt,
                  title: 'Automations',
                  subtitle: automationLocalNote,
                  value: automations == null ? null : '${chosenAutomations(automations)} saved',
                  onTap: () => context.push(Routes.automations),
                ),
                SxListRow(
                  icon: TablerIcons.bookmark,
                  title: 'Saved rules',
                  value: profile.hasValue ? '${parseSavedRules(profile.value?.contentMd).length}' : null,
                  onTap: () => context.push(Routes.rules),
                ),
                SxListRow(
                  icon: TablerIcons.book_2,
                  title: 'What sellix knows',
                  value: knowsValue,
                  onTap: () => context.push(Routes.shopprofile),
                ),
                SxListRow(
                  icon: TablerIcons.clock,
                  title: 'Opening hours',
                  value: onboarding == null ? null : hoursSummary(onboarding.answers),
                  onTap: () => context.push(Routes.hours),
                ),
              ],
            ),
          ),
        ),
        const SettingsGroupLabel('Connections'),
        Mx(
          child: SxFadeUp(
            index: 2,
            child: SxGroup(
              children: [
                SxListRow(
                  leading: _BrandTile(SxBrand.instagram),
                  title: 'Instagram',
                  value: channelWorks(instagram) ? 'Connected' : null,
                  trailing: channelWorks(instagram)
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: SxSpace.s8,
                          children: [
                            Text(
                              instagram == null ? 'Connect' : 'Reconnect',
                              style: SxText.caption.copyWith(color: p.errorText),
                            ),
                            Icon(TablerIcons.chevron_right, size: 20, color: p.textSecondary),
                          ],
                        ),
                  onTap: () => context.push(Routes.channels),
                ),
                SxListRow(
                  leading: _BrandTile(SxBrand.whatsapp),
                  title: 'WhatsApp',
                  value: channelWorks(whatsapp) ? 'Connected' : 'Not available yet',
                  onTap: () => context.push(Routes.channels),
                ),
                SxListRow(
                  icon: TablerIcons.credit_card,
                  title: 'Payments',
                  value: onboarding == null ? null : (paymentNames.isEmpty ? 'Not set' : paymentNames.join(', ')),
                  onTap: () => context.push(Routes.payments),
                ),
              ],
            ),
          ),
        ),
        const SettingsGroupLabel('App'),
        Mx(
          child: SxFadeUp(
            index: 3,
            child: SxGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(SxSpace.card),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: SxSpace.s8,
                    children: [
                      Row(
                        spacing: SxSpace.s12,
                        children: [
                          const SxIconTile(icon: TablerIcons.sun_moon, size: 40, radius: SxSpace.s12),
                          Text('Appearance', style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                        ],
                      ),
                      SxSegmented<ThemeMode>(
                        segments: const [
                          SxSegment(ThemeMode.system, 'System'),
                          SxSegment(ThemeMode.light, 'Light'),
                          SxSegment(ThemeMode.dark, 'Dark'),
                        ],
                        value: themeMode,
                        onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode),
                      ),
                    ],
                  ),
                ),
                SxListRow(
                  icon: TablerIcons.language,
                  title: 'App language',
                  value: 'English',
                  onTap: _pickLanguage,
                ),
                SxListRow(
                  icon: TablerIcons.bell,
                  title: 'Morning reminder',
                  subtitle: automationLocalNote,
                  value: alerts.morning,
                  onTap: () => _pickMorning(alerts),
                ),
                SxListRow(
                  icon: TablerIcons.moon,
                  title: 'Quiet hours',
                  subtitle: automationLocalNote,
                  value: alerts.quietWords,
                  onTap: () => _pickQuiet(alerts),
                ),
              ],
            ),
          ),
        ),
        const SettingsGroupLabel('Help'),
        Mx(
          child: SxFadeUp(
            index: 4,
            child: SxGroup(
              children: [
                SxListRow(icon: TablerIcons.help_circle, title: 'Help and how-tos', onTap: _openHelp),
                SxListRow(icon: TablerIcons.logout, title: 'Sign out', chevron: false, onTap: _signOut),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: SxSpace.s20),
          child: Text(
            'sellix 0.1.0',
            textAlign: TextAlign.center,
            style: SxText.micro.copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _BrandTile extends StatelessWidget {
  const _BrandTile(this.brand);

  final SxBrand brand;

  @override
  Widget build(BuildContext context) => SxIconTile(size: 40, radius: SxSpace.s12, child: SxBrandIcon(brand));
}

class _QuietSheet extends StatefulWidget {
  const _QuietSheet({required this.from, required this.to});

  final String from;
  final String to;

  @override
  State<_QuietSheet> createState() => _QuietSheetState();
}

class _QuietSheetState extends State<_QuietSheet> {
  late String _from = widget.from;
  late String _to = widget.to;

  Widget _chips(String current, ValueChanged<String> pick) => Wrap(
    spacing: SxSpace.s8,
    runSpacing: SxSpace.s8,
    children: [
      for (final time in timeChoices(current))
        SxPickChip(label: time, selected: time == current, onTap: () => setState(() => pick(time))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final style = SxText.label.copyWith(color: context.sx.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s8,
      children: [
        Text('Starts at', style: style),
        _chips(_from, (t) => _from = t),
        const SizedBox(height: SxSpace.s8),
        Text('Ends at', style: style),
        _chips(_to, (t) => _to = t),
        const SizedBox(height: SxSpace.s8),
        const SxLocalOnlyNote(),
        const SizedBox(height: SxSpace.s8),
        SxButton(
          label: 'Save quiet hours',
          fullWidth: true,
          onTap: () => Navigator.of(context).pop((_from, _to)),
        ),
      ],
    );
  }
}
