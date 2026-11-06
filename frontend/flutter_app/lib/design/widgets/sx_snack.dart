import 'dart:async';

import 'package:flutter/material.dart';

import '../sx_theme.dart';
import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_pressable.dart';

/// Shows the app's one snackbar (DESIGN.md 9.21, prototype `snack()`), replacing any other.
///
/// [aboveBar] true (default) sits above the nav, a bottom CTA or a composer; false drops it
/// to the bottom for screens with none of those. It sits above an open sheet by itself.
/// [sellix] paints the icon signal green; leave it null to detect "sellix" in the text.
/// With an [action] (usually "Undo") it survives navigation, like the prototype's.
void showSxSnack(
  BuildContext context,
  String text, {
  IconData? icon,
  String? action,
  VoidCallback? onAction,
  bool? sellix,
  bool aboveBar = true,
  Duration duration = const Duration(seconds: 4),
}) {
  SxSnackHost._show(
    Overlay.of(context, rootOverlay: true),
    _SnackData(
      text: text,
      icon: icon,
      action: action,
      onAction: onAction,
      sellix: sellix ?? text.toLowerCase().contains('sellix'),
      aboveBar: aboveBar,
      duration: duration,
    ),
  );
}

/// Hides the snackbar now.
void hideSxSnack() => SxSnackHost._hide();

/// Plumbing shared with the sheet and the router. Feature code uses [showSxSnack].
abstract final class SxSnackHost {
  static OverlayEntry? _entry;
  static GlobalKey<_SnackViewState>? _view;
  static Timer? _timer;
  static bool _hasAction = false;
  static DateTime _shownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The sheet that is open now, so the snackbar can sit above it.
  static GlobalKey? openSheetKey;

  static void _show(OverlayState overlay, _SnackData data) {
    _removeNow();
    final key = GlobalKey<_SnackViewState>();
    final entry = OverlayEntry(builder: (_) => _SnackView(key: key, data: data));
    _entry = entry;
    _view = key;
    _hasAction = data.action != null;
    _shownAt = DateTime.now();
    overlay.insert(entry);
    _timer = Timer(data.duration, _hide);
  }

  static void _hide() {
    _timer?.cancel();
    _timer = null;
    final state = _view?.currentState;
    if (state == null) {
      _removeNow();
      return;
    }
    final entry = _entry;
    _entry = null;
    _view = null;
    _hasAction = false;
    state.dismiss().whenComplete(() {
      if (entry != null && entry.mounted) entry.remove();
    });
  }

  static void _removeNow() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    if (entry != null && entry.mounted) entry.remove();
    _entry = null;
    _view = null;
    _hasAction = false;
  }

  /// Called on navigation: a snackbar does not follow you to the next screen, unless it has
  /// an Undo that still applies. One shown a moment ago belongs to the screen being opened.
  static void clearOnNavigation() {
    if (_entry == null || _hasAction) return;
    if (DateTime.now().difference(_shownAt) < const Duration(milliseconds: 700)) return;
    _hide();
  }

  static double? _sheetHeight() {
    final box = openSheetKey?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : null;
  }
}

/// Router observer that applies [SxSnackHost.clearOnNavigation].
class SxSnackNavigatorObserver extends NavigatorObserver {
  bool _isPage(Route<dynamic>? r) => r is PageRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) SxSnackHost.clearOnNavigation();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) SxSnackHost.clearOnNavigation();
  }
}

class _SnackData {
  const _SnackData({
    required this.text,
    required this.icon,
    required this.action,
    required this.onAction,
    required this.sellix,
    required this.aboveBar,
    required this.duration,
  });

  final String text;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  final bool sellix;
  final bool aboveBar;
  final Duration duration;
}

class _SnackView extends StatefulWidget {
  const _SnackView({super.key, required this.data});

  final _SnackData data;

  @override
  State<_SnackView> createState() => _SnackViewState();
}

class _SnackViewState extends State<_SnackView> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SxMotion.slow)..forward();

  Future<void> dismiss() => mounted ? _c.reverse() : Future.value();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final d = widget.data;
    final mq = MediaQuery.of(context);
    final safe = mq.padding.bottom;
    final sheet = SxSnackHost._sheetHeight();
    final barHeight = SxSpace.navHeight + SxSpace.navGap;
    final bottom = sheet != null
        ? sheet + SxSpace.s8 + mq.viewInsets.bottom
        : mq.viewInsets.bottom + safe + SxSpace.navGap + (d.aboveBar ? barHeight : 0);
    final scale = CurvedAnimation(parent: _c, curve: SxMotion.spring, reverseCurve: SxMotion.curve);
    return Positioned(
      left: SxSpace.screen,
      right: SxSpace.screen,
      bottom: bottom,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: SxMotion.curve),
        child: AnimatedBuilder(
          animation: scale,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, 20 * (1 - scale.value)),
            child: Transform.scale(scale: 0.96 + 0.04 * scale.value, child: child),
          ),
          child: Semantics(
            liveRegion: true,
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: EdgeInsets.only(left: d.icon == null ? SxSpace.s20 : 12, right: SxSpace.s8, top: 8, bottom: 8),
                decoration: sxFloating(p, p.anchor).copyWith(borderRadius: BorderRadius.circular(26)),
                child: Row(
                  children: [
                    if (d.icon != null) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(color: d.sellix ? p.signal : p.anchorRaised, shape: BoxShape.circle),
                        child: Icon(d.icon, size: 16, color: d.sellix ? p.onSignal : p.onAnchor),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: Text(d.text, style: SxText.bodyS.copyWith(color: p.onAnchor))),
                    if (d.action != null) ...[
                      const SizedBox(width: SxSpace.s8),
                      SxPressable(
                        small: true,
                        onTap: () {
                          hideSxSnack();
                          d.onAction?.call();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Text(d.action!, style: SxText.label.copyWith(color: p.signalOnAnchor)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
