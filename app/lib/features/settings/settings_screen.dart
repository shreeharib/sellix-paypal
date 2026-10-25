import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../today/today_providers.dart';

final meProvider = FutureProvider.autoDispose<Me>((ref) => ref.watch(sellixApiProvider).me());

final shopProfileProvider = FutureProvider.autoDispose<ShopProfile?>(
  (ref) => ref.watch(sellixApiProvider).shopProfile(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: AsyncView(
        value: me,
        onRetry: () => ref.invalidate(meProvider),
        data: (data) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(Insets.md),
            children: [
              _ShopName(merchant: data.merchant),
              const SizedBox(height: Insets.md),
              _AgentSwitch(enabled: data.merchant.agentEnabled),
              const SizedBox(height: Insets.lg),
              const _ShopProfileEditor(),
              const SizedBox(height: Insets.lg),
              Text(l10n.settingsChannels, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Insets.sm),
              for (final channel in data.channels)
                Card(
                  child: ListTile(
                    leading: Icon(
                      channel.status == 'active' ? Icons.check_circle : Icons.error_outline,
                      color: channel.status == 'active'
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(l10n.settingsInstagram(channel.username ?? '')),
                    subtitle: Text(channel.status),
                  ),
                ),
              const SizedBox(height: Insets.xl),
              OutlinedButton.icon(
                onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                icon: const Icon(Icons.logout),
                label: Text(l10n.settingsSignOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopName extends ConsumerStatefulWidget {
  const _ShopName({required this.merchant});

  final Merchant merchant;

  @override
  ConsumerState<_ShopName> createState() => _ShopNameState();
}

class _ShopNameState extends ConsumerState<_ShopName> {
  late final _name = TextEditingController(text: widget.merchant.name);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == widget.merchant.name) return;
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).updateMerchant(name: name);
      ref.invalidate(meProvider);
      if (mounted) showMessage(context, context.l10n.commonSaved);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _name,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: context.l10n.settingsShopName,
          suffixIcon: IconButton(
            onPressed: _saving ? null : _save,
            tooltip: context.l10n.commonSave,
            icon: const Icon(Icons.check),
          ),
        ),
      );
}

class _AgentSwitch extends ConsumerStatefulWidget {
  const _AgentSwitch({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_AgentSwitch> createState() => _AgentSwitchState();
}

class _AgentSwitchState extends ConsumerState<_AgentSwitch> {
  bool _saving = false;

  Future<void> _toggle(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).updateMerchant(agentEnabled: enabled);
      ref
        ..invalidate(meProvider)
        ..invalidate(todayProvider);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: SwitchListTile(
          value: widget.enabled,
          onChanged: _saving ? null : _toggle,
          title: Text(context.l10n.todayAgentSwitchLabel),
          subtitle: Text(context.l10n.settingsAgentHint),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Insets.radius)),
        ),
      );
}

class _ShopProfileEditor extends ConsumerStatefulWidget {
  const _ShopProfileEditor();

  @override
  ConsumerState<_ShopProfileEditor> createState() => _ShopProfileEditorState();
}

class _ShopProfileEditorState extends ConsumerState<_ShopProfileEditor> {
  final _content = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _content.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(sellixApiProvider).saveShopProfile(text);
      ref.invalidate(shopProfileProvider);
      if (mounted) showMessage(context, context.l10n.settingsProfileSaved);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final profile = ref.watch(shopProfileProvider);
    if (!_loaded && profile.hasValue) {
      _content.text = profile.value?.contentMd ?? '';
      _loaded = true;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.settingsProfile, style: theme.textTheme.titleMedium),
        const SizedBox(height: Insets.xs),
        Text(
          l10n.settingsProfileHint,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _content,
          enabled: profile.hasValue,
          minLines: 6,
          maxLines: 16,
          maxLength: 8000,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: _saving || !profile.hasValue ? null : _save,
            child: Text(l10n.commonSave),
          ),
        ),
      ],
    );
  }
}
