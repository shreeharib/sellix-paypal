/// "Server": which sellix server the app talks to. Opened from the sign-in screen and Profile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/server_config.dart';
import '../../design/design.dart';

/// The host only, for a row's value: `api.yourshop.com`.
String serverHost(String url) {
  final uri = Uri.tryParse(url);
  return uri == null || uri.host.isEmpty ? url : (uri.hasPort ? '${uri.host}:${uri.port}' : uri.host);
}

/// Shows the sheet; a new address is applied after it closes, so the sign-out that comes with it
/// can't pull the screen out from under the sheet.
Future<void> showServerSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final url = await showSxSheet<String>(
    context,
    title: 'sellix server',
    subtitle: 'The address this app talks to. Change it only if your team gave you another one.',
    builder: (_) => const _ServerSheet(),
  );
  if (url == null || url == container.read(serverUrlProvider)) return;
  final signedIn = container.read(authControllerProvider).value == AuthStatus.signedIn;
  await container.read(authControllerProvider.notifier).changeServer(url);
  if (!context.mounted) return;
  showSxSnack(
    context,
    signedIn ? 'Now using ${serverHost(url)}. Sign in again.' : 'Now using ${serverHost(url)}.',
    icon: TablerIcons.server,
    sellix: false,
    aboveBar: false,
  );
}

enum _Check { none, checking, ok, unreachable }

class _ServerSheet extends ConsumerStatefulWidget {
  const _ServerSheet();

  @override
  ConsumerState<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends ConsumerState<_ServerSheet> {
  late final _url = TextEditingController(text: ref.read(serverUrlProvider));
  String? _error;
  _Check _check = _Check.none;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String? _validated() {
    final problem = serverUrlError(_url.text);
    setState(() => _error = problem);
    return problem == null ? normalizeServerUrl(_url.text) : null;
  }

  Future<void> _runCheck() async {
    final url = _validated();
    if (url == null) return;
    setState(() => _check = _Check.checking);
    final ok = await ref.read(serverCheckProvider)(url);
    if (mounted) setState(() => _check = ok ? _Check.ok : _Check.unreachable);
  }

  void _use() {
    final url = _validated();
    if (url != null) Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final current = ref.watch(serverUrlProvider);
    final fallback = ref.read(serverUrlProvider.notifier).buildDefault;
    final signedIn = ref.watch(authControllerProvider).value == AuthStatus.signedIn;
    final (icon, line, color) = switch (_check) {
      _Check.ok => (TablerIcons.circle_check, 'sellix answers at this address.', p.successText),
      _Check.unreachable => (TablerIcons.cloud_off, 'Can’t reach this address.', p.errorText),
      _Check.checking => (TablerIcons.clock, 'Checking…', p.textSecondary),
      _Check.none => (null, null, p.textSecondary),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SxSpace.s12,
      children: [
        SxKeyValue(label: 'Now', value: current),
        SxField(
          controller: _url,
          label: 'Server address',
          hint: 'https://api.yourshop.com',
          keyboardType: TextInputType.url,
          errorText: _error,
          onChanged: (_) {
            if (_error != null || _check != _Check.none) {
              setState(() {
                _error = null;
                _check = _Check.none;
              });
            }
          },
        ),
        if (line != null)
          Semantics(
            liveRegion: true,
            child: Row(
              spacing: SxSpace.s8,
              children: [
                Icon(icon, size: 18, color: color),
                Expanded(child: Text(line, style: SxText.bodyS.copyWith(color: color))),
              ],
            ),
          ),
        if (signedIn)
          Text(
            'Changing the server signs you out. Sign in again on the new one.',
            style: SxText.caption.copyWith(color: p.textSecondary),
          ),
        if (current != fallback)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SxLinkButton(
              label: 'Use the default (${serverHost(fallback)})',
              onTap: () => setState(() {
                _url.text = fallback;
                _error = null;
                _check = _Check.none;
              }),
            ),
          ),
        SxButtonRow(
          children: [
            SxButton(
              label: 'Check',
              icon: TablerIcons.plug_connected,
              kind: SxButtonKind.secondary,
              loading: _check == _Check.checking,
              onTap: _check == _Check.checking ? null : _runCheck,
            ),
            SxButton(label: 'Use this server', onTap: _use),
          ],
        ),
      ],
    );
  }
}
