import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../design/design.dart';
import 'sign_in_flow.dart';

class _Copy {
  const _Copy(this.values, this.title, this.body, this.note, this.cta);

  final List<String> values;
  final String title;
  final String body;
  final String note;
  final String cta;
}

const _english = _Copy(
  ['Replies in Tanglish, Tamil, Hinglish, English', 'Takes the order, holds stock, collects payment', 'Asks you before it guesses'],
  'Now connect your shop’s Instagram.',
  'sellix answers Instagram DMs in your customer’s language, takes the order and collects payment. When it is not sure, it asks you.',
  'Use your shop’s Instagram professional account.',
  'Continue with Instagram',
);

const _tamilCopy = _Copy(
  ['Tanglish, தமிழ், Hinglish, English-ல் பதில்', 'ஆர்டர் எடுக்கும், இருப்பை வைத்திருக்கும், பணம் வசூலிக்கும்', 'யூகிக்கும் முன் உங்களிடம் கேட்கும்'],
  'இப்போது உங்கள் கடையின் Instagram-ஐ இணைக்கவும்.',
  'வாடிக்கையாளரின் மொழியில் sellix பதில் சொல்லும், ஆர்டர் எடுக்கும், பணம் வசூலிக்கும். உறுதியில்லையெனில் உங்களிடம் கேட்கும்.',
  'உங்கள் கடையின் Instagram professional கணக்கைப் பயன்படுத்துங்கள்.',
  'Instagram மூலம் தொடரவும்',
);

const _valueIcons = [TablerIcons.language, TablerIcons.receipt, TablerIcons.hand_stop];

/// The pre-brief: what happens on Instagram, and what sellix can and cannot do. Its button starts
/// the real login, which runs on instagram.com.
Future<void> showPrebriefSheet(BuildContext context, WidgetRef ref) {
  return showSxSheet<void>(
    context,
    title: 'Connect your Instagram',
    subtitle: 'This takes about a minute.',
    builder: (sheet) {
      final p = sheet.sx;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, step) in const [
            ('Log in on Instagram', 'Use your shop’s professional account.'),
            ('Allow messages', 'So sellix can read and answer your DMs.'),
            ('Come back here', 'You tell sellix about your shop next.'),
          ].indexed) ...[
            SxFadeUp(
              index: i,
              child: Row(
                children: [
                  SxIconTile(
                    size: 36,
                    radius: SxRadius.pill,
                    child: Text('${i + 1}', style: SxText.label.copyWith(color: p.textPrimary)),
                  ),
                  const SizedBox(width: SxSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.$1, style: SxText.bodyStrong.copyWith(color: p.textPrimary)),
                        Text(step.$2, style: SxText.caption.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SxSpace.s12),
          ],
          const SizedBox(height: SxSpace.s4),
          SxFadeUp(
            index: 3,
            child: SxCard(
              color: p.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('sellix will', style: SxText.label.copyWith(color: p.textPrimary)),
                  const SizedBox(height: SxSpace.s8),
                  const PermissionLine(TablerIcons.check, 'Read and answer your shop’s DMs'),
                  const PermissionLine(TablerIcons.check, 'See which post or story a customer means'),
                  const PermissionLine(TablerIcons.check, 'Send order and payment messages'),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: SxSpace.s12),
                    child: Divider(height: 1, thickness: 1, color: p.line),
                  ),
                  Text('sellix will never', style: SxText.label.copyWith(color: p.textPrimary)),
                  const SizedBox(height: SxSpace.s8),
                  const PermissionLine(TablerIcons.x, 'Post on your account'),
                  const PermissionLine(TablerIcons.x, 'Run ads or spend money'),
                  const PermissionLine(TablerIcons.x, 'Message people who did not message you'),
                ],
              ),
            ),
          ),
          const SizedBox(height: SxSpace.s12),
          SxFadeUp(
            index: 4,
            child: Row(
              children: [
                Icon(TablerIcons.lock, size: 16, color: p.textSecondary),
                const SizedBox(width: SxSpace.s8),
                Expanded(
                  child: Text(
                    'Your password stays with Instagram. sellix never sees it.',
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SxSpace.s16),
          SxButton(
            label: 'Continue to Instagram',
            icon: TablerIcons.external_link,
            fullWidth: true,
            onTap: () {
              Navigator.of(sheet).pop();
              ref.read(signInFlowProvider.notifier).request();
              context.go(Routes.connecting);
            },
          ),
        ],
      );
    },
  );
}

class PermissionLine extends StatelessWidget {
  const PermissionLine(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: p.textPrimary),
          const SizedBox(width: SxSpace.s8),
          Expanded(child: Text(text, style: SxText.bodyS.copyWith(color: p.textPrimary))),
        ],
      ),
    );
  }
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.openBrief = false});

  /// Opens the pre-brief sheet on arrival (the prebrief route).
  final bool openBrief;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _tamil = false;

  @override
  void initState() {
    super.initState();
    if (widget.openBrief) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(showPrebriefSheet(context, ref));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final t = _tamil ? _tamilCopy : _english;
    return SxScaffold(
      statusOnAnchor: true,
      safeTop: false,
      floating: SxBottomCta(
        label: t.cta,
        icon: TablerIcons.brand_instagram,
        onTap: () {
          HapticFeedback.lightImpact();
          showPrebriefSheet(context, ref);
        },
      ),
      body: SxScrollList(
        children: [
          Container(
            color: p.anchor,
            padding: EdgeInsets.fromLTRB(
              SxSpace.screen,
              MediaQuery.paddingOf(context).top + SxSpace.s12,
              SxSpace.screen,
              SxSpace.s20,
            ),
            child: Row(
              children: [
                const SxLogo(size: 36, surface: SxLogoSurface.anchor),
                const SizedBox(width: SxSpace.s8),
                Expanded(
                  child: Text(
                    'sellix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SxText.titleM.copyWith(color: p.onAnchor),
                  ),
                ),
                const SizedBox(width: SxSpace.s8),
                _LangToggle(tamil: _tamil, onChanged: (v) => setState(() => _tamil = v)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.screen, SxSpace.s24, SxSpace.screen, 0),
            child: AnimatedSwitcher(
              duration: SxMotion.base,
              child: Column(
                key: ValueKey(_tamil),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.title, style: SxText.titleL.copyWith(color: p.textPrimary)),
                  const SizedBox(height: SxSpace.s12),
                  Text(t.body, style: SxText.bodyS.copyWith(color: p.textSecondary)),
                  const SizedBox(height: SxSpace.s20),
                  for (final (i, value) in t.values.indexed) ...[
                    SxFadeUp(
                      index: i,
                      child: Row(
                        children: [
                          SxIconTile(icon: _valueIcons[i]),
                          const SizedBox(width: SxSpace.s12),
                          Expanded(child: Text(value, style: SxText.bodyStrong.copyWith(color: p.textPrimary))),
                        ],
                      ),
                    ),
                    const SizedBox(height: SxSpace.s12),
                  ],
                  const SizedBox(height: SxSpace.s8),
                  Text(
                    t.note,
                    textAlign: TextAlign.center,
                    style: SxText.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.tamil, required this.onChanged});

  final bool tamil;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    Widget option(String label, bool value) {
      final on = tamil == value;
      return Semantics(
        selected: on,
        button: true,
        child: SxPressable(
          small: true,
          onTap: on ? null : () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: SxSpace.s12, vertical: 6),
            decoration: BoxDecoration(
              color: on ? p.onAnchor : null,
              borderRadius: BorderRadius.circular(SxRadius.pill),
            ),
            child: Text(label, style: SxText.micro.copyWith(color: on ? p.anchor : p.onAnchorSecondary)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.anchorRaised, borderRadius: BorderRadius.circular(SxRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [option('English', false), option('தமிழ்', true)],
      ),
    );
  }
}
