import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sx_theme.dart';
import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_chip.dart';
import 'sx_motion.dart';
import 'sx_pressable.dart';

class SxNavItem {
  const SxNavItem({required this.icon, required this.label, this.badge = 0, this.liveDot = false, this.badgeWord});

  final IconData icon;
  final String label;
  final int badge;

  /// 8 px signal dot, for live AI chats. A badge takes its place when there is one.
  final bool liveDot;

  /// Spoken after the count: "Chats, 3 need you".
  final String? badgeWord;
}

/// DESIGN.md 9.18. The active tab's column is 2.4 wide; its pill slides in 240 ms.
/// Position it yourself; `AppShell` in lib/core already does.
class SxFloatingNav extends StatelessWidget {
  const SxFloatingNav({super.key, required this.items, required this.currentIndex, required this.onTap});

  final List<SxNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _activeFlex = 2.4;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      height: SxSpace.navHeight,
      padding: const EdgeInsets.symmetric(horizontal: SxSpace.s8),
      decoration: sxFloating(p, p.nav),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final unit = constraints.maxWidth / (items.length - 1 + _activeFlex);
          final activeWidth = unit * _activeFlex;
          double leftOf(int i) => i <= currentIndex ? i * unit : (i - 1) * unit + activeWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedPositioned(
                duration: SxMotion.nav,
                curve: SxMotion.move,
                top: 8,
                bottom: 8,
                left: leftOf(currentIndex) + 2,
                width: activeWidth - 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: p.navActive, borderRadius: BorderRadius.circular(SxRadius.pill)),
                ),
              ),
              for (var i = 0; i < items.length; i++)
                AnimatedPositioned(
                  duration: SxMotion.nav,
                  curve: SxMotion.move,
                  top: 8,
                  bottom: 8,
                  left: leftOf(i),
                  width: i == currentIndex ? activeWidth : unit,
                  child: _Tab(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTap(i);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.active, required this.onTap});

  final SxNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final fg = active ? p.onNavActive : p.navIcon;
    final count = item.badge;
    final label = count > 0 ? '${item.label}, $count ${item.badgeWord ?? ''}'.trim() : item.label;
    return Semantics(
      selected: active,
      child: SxPressable(
        small: true,
        haptic: false,
        onTap: onTap,
        semanticLabel: label,
        child: ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: active ? 20 : 22, color: fg),
                  Flexible(
                    child: ClipRect(
                      child: AnimatedSize(
                        duration: SxMotion.nav,
                        curve: SxMotion.move,
                        alignment: AlignmentDirectional.centerStart,
                        child: active
                            ? Padding(
                                padding: const EdgeInsets.only(left: SxSpace.s8),
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.fade,
                                  style: SxText.label.copyWith(color: fg),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
              if (!active && count > 0)
                Positioned(
                  top: 4,
                  child: Transform.translate(offset: const Offset(13, 0), child: SxBadge(count: count, size: 18)),
                )
              else if (!active && item.liveDot)
                Positioned(
                  top: 10,
                  child: Transform.translate(offset: const Offset(12, 0), child: const SxPulseDot(size: 8)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
