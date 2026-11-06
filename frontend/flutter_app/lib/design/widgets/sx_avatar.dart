import 'package:flutter/material.dart';

import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_brand_icon.dart';
import 'sx_pressable.dart';

/// "Priya Nair" -> "PN", "@priya.nair" -> "PN", "" -> "?". For customer handles and shop names.
String sxInitials(String name) {
  final words = name
      .replaceAll('@', '')
      .split(RegExp(r'[\s._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final letters = words.take(2).map((w) => w.characters.first.toUpperCase());
  return letters.join();
}

/// Plain circle with initials from [name]. Defaults: `tile` with `textPrimary`.
class SxInitialsAvatar extends StatelessWidget {
  const SxInitialsAvatar({super.key, required this.name, this.size = 36, this.background, this.foreground});

  final String name;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background ?? p.tile, shape: BoxShape.circle),
      child: Text(
        sxInitials(name),
        maxLines: 1,
        style: SxText.caption.copyWith(
          color: foreground ?? p.textPrimary,
          fontSize: size * 0.36,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Merchant avatar (DESIGN.md 9.3): 44 px, shop initials in `onAnchor` on `anchor`.
class SxAvatar extends StatelessWidget {
  const SxAvatar({super.key, required this.name, this.size = 44, this.onTap, this.semanticLabel = 'Profile'});

  final String name;
  final double size;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final avatar = SxInitialsAvatar(name: name, size: size, background: p.anchor, foreground: p.onAnchor);
    if (onTap == null) return avatar;
    return SxPressable(small: true, onTap: onTap, semanticLabel: semanticLabel, child: avatar);
  }
}

/// Customer avatar: 36 px (56 with [large]), attention colours when [needsYou],
/// optional channel badge at the bottom right.
class SxCustomerAvatar extends StatelessWidget {
  const SxCustomerAvatar({
    super.key,
    required this.name,
    this.needsYou = false,
    this.large = false,
    this.channel,
  });

  final String name;
  final bool needsYou;
  final bool large;
  final SxBrand? channel;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final size = large ? 56.0 : 36.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SxInitialsAvatar(
            name: name,
            size: size,
            background: needsYou ? p.attentionTint : p.tile,
            foreground: needsYou ? p.attentionText : p.textPrimary,
          ),
          if (channel != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.card,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: p.page, spreadRadius: 2)],
                ),
                child: SxBrandIcon(channel!, size: 13),
              ),
            ),
        ],
      ),
    );
  }
}
