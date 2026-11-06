import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the floating nav shows on its Chats and Orders tabs.
class NavBadges {
  const NavBadges({this.chatsNeedYou = 0, this.chatsLive = false, this.ordersToAct = 0});

  final int chatsNeedYou;
  final bool chatsLive;
  final int ordersToAct;
}

/// Starts empty. Screens that load chats, questions or orders push their real counts here;
/// nothing is invented, so the bar shows no badge until something real is known.
class NavBadgesController extends Notifier<NavBadges> {
  @override
  NavBadges build() => const NavBadges();

  void update({int? chatsNeedYou, bool? chatsLive, int? ordersToAct}) {
    state = NavBadges(
      chatsNeedYou: chatsNeedYou ?? state.chatsNeedYou,
      chatsLive: chatsLive ?? state.chatsLive,
      ordersToAct: ordersToAct ?? state.ordersToAct,
    );
  }
}

final navBadgesProvider = NotifierProvider<NavBadgesController, NavBadges>(NavBadgesController.new);
