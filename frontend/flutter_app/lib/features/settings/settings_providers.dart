/// Shop data shared by the settings screens. Other features may import [meProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../design/design.dart';

/// The signed-in merchant and their channels.
final meProvider = FutureProvider.autoDispose<Me>((ref) => ref.watch(sellixApiProvider).me());

/// The onboarding answers: shop details, hours, tone, policies and UPI.
final onboardingProvider = FutureProvider.autoDispose<Onboarding>(
  (ref) => ref.watch(sellixApiProvider).onboarding(),
);

/// The newest version of what the agent reads. Null until something is written.
final shopProfileProvider = FutureProvider.autoDispose<ShopProfile?>(
  (ref) => ref.watch(sellixApiProvider).shopProfile(),
);

/// The most an answer field holds on the backend (`modules/shop_profile/schemas.py`).
const answerShortLimit = 200;
const answerLongLimit = 1500;
const shopNameLimit = 120;

/// Changes some onboarding answers and keeps every other one.
///
/// A PUT replaces all the answers, so this reads the current ones first rather than trusting what a
/// screen loaded earlier. `complete` is left out on purpose: finishing setup belongs to onboarding.
/// The backend also rewrites the shop profile from the answers, keeping its "Saved answers" section.
///
/// Takes the container, not a `WidgetRef`, because an Undo can run after its screen has closed.
Future<Onboarding> saveAnswers(
  ProviderContainer container,
  OnboardingAnswers Function(OnboardingAnswers current) edit, {
  String? shopName,
}) async {
  final api = container.read(sellixApiProvider);
  final current = await api.onboarding();
  final saved = await api.saveOnboarding(
    shopName: shopName ?? current.shopName,
    answers: edit(current.answers),
  );
  container
    ..invalidate(onboardingProvider)
    ..invalidate(shopProfileProvider)
    ..invalidate(meProvider);
  return saved;
}

/// The container of the nearest scope, for work that may outlive the screen.
ProviderContainer containerOf(BuildContext context) => ProviderScope.containerOf(context, listen: false);

/// The prototype's save ending: the CTA shows its check, then back with a snackbar.
Future<void> finishSave(BuildContext context, String? message, {required String fallback}) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (!context.mounted) return;
  if (message != null) showSxSnack(context, message, icon: TablerIcons.check);
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// "updated today" or "updated 15 Jan".
String updatedWords(DateTime when) {
  final day = dayLabel(when);
  return 'updated ${day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : day}';
}

/// Trimmed text, or null for "clear this answer".
String? blankToNull(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Channel? channelOf(List<Channel> channels, String name) {
  for (final channel in channels) {
    if (channel.channel == name) return channel;
  }
  return null;
}

/// Can sellix read and answer on this channel right now?
bool channelWorks(Channel? channel, {DateTime? now}) {
  if (channel == null || channel.status != 'active') return false;
  final expires = channel.tokenExpiresAt;
  return expires == null || expires.isAfter(now ?? DateTime.now());
}

/// A small grey label above a settings group.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SxSpace.s24, SxSpace.s20, SxSpace.s24, SxSpace.s8),
    child: Text(text, style: SxText.micro.copyWith(color: context.sx.textSecondary)),
  );
}

/// The screen margin.
class Mx extends StatelessWidget {
  const Mx({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: SxSpace.screen), child: child);
}

/// Every hour from 5 AM to 11 PM, plus [current] if it is not on the hour.
List<String> timeChoices(String? current) {
  final list = [
    for (var h = 5; h <= 23; h++) '${h % 12 == 0 ? 12 : h % 12}:00 ${h >= 12 ? 'PM' : 'AM'}',
  ];
  return current != null && !list.contains(current) ? [current, ...list] : list;
}

/// Pick one time. Closes on the pick and returns it.
Future<String?> showTimeSheet(BuildContext context, {required String title, String? current, Widget? note}) =>
    showSxSheet<String>(
      context,
      title: title,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SxSpace.s12,
        children: [
          Wrap(
            spacing: SxSpace.s8,
            runSpacing: SxSpace.s8,
            children: [
              for (final time in timeChoices(current))
                SxPickChip(
                  label: time,
                  selected: time == current,
                  onTap: () => Navigator.of(sheet).pop(time),
                ),
            ],
          ),
          ?note,
        ],
      ),
    );
