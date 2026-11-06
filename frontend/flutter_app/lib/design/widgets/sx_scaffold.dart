import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';

/// Bottom padding for scroll content under a floating bar: 112 plus the safe area.
double sxBottomInset(BuildContext context) => SxSpace.bottomInset + MediaQuery.paddingOf(context).bottom;

/// The screen frame from skill.md: status bar style, `page` background, top safe area with the
/// prototype's fade under the status bar, and a slot for a floating bar (CTA or composer).
/// Root tabs leave [floating] empty: the shell draws the nav.
class SxScaffold extends StatelessWidget {
  const SxScaffold({
    super.key,
    required this.body,
    this.floating,
    this.floatingMargin = SxSpace.screen,
    this.statusOnAnchor = false,
    this.safeTop = true,
    this.background,
  });

  final Widget body;
  final Widget? floating;

  /// 20 for a CTA, 16 for a composer.
  final double floatingMargin;

  /// The top of the screen is an anchor block: light status icons in the light theme, no fade.
  final bool statusOnAnchor;

  /// False when the body draws under the status bar (anchor headers, galleries).
  final bool safeTop;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final darkIcons = statusOnAnchor ? !isLight : isLight;
    final mq = MediaQuery.of(context);
    final bg = background ?? p.page;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkIcons ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            Positioned.fill(child: SafeArea(top: safeTop, bottom: false, child: body)),
            if (safeTop && !statusOnAnchor)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: mq.padding.top,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.72, 1],
                        colors: [bg, bg.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            if (floating != null)
              Positioned(
                left: floatingMargin,
                right: floatingMargin,
                bottom: mq.padding.bottom + SxSpace.navGap,
                child: floating!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Screen list with the bottom inset, and pull-to-refresh when [onRefresh] is set.
/// Always scrollable so an empty list can still be pulled.
class SxScrollList extends StatelessWidget {
  const SxScrollList({
    super.key,
    required this.children,
    this.onRefresh,
    this.controller,
    this.bottomInset = true,
    this.padding,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;

  /// False on task screens with nothing floating.
  final bool bottomInset;

  /// Replaces the default padding, which has no side margin: children set their own.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: padding ??
          EdgeInsets.only(bottom: bottomInset ? sxBottomInset(context) : SxSpace.s40),
      children: children,
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(
      color: p.textPrimary,
      backgroundColor: p.card,
      elevation: 0,
      onRefresh: onRefresh!,
      child: list,
    );
  }
}
