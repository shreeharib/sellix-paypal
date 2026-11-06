import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../tokens/sx_palette.dart';

/// The surface the logo sits on; it sets the glyph's colours (prototype `ctx-*`).
enum SxLogoSurface { page, card, anchor, photo }

/// App logo. Light theme: the glyph alone, coloured for its surface.
/// Dark theme: the full app-icon tile, whose colours are fixed brand colours.
class SxLogo extends StatelessWidget {
  const SxLogo({super.key, this.size = 44, this.surface = SxLogoSurface.page, this.semanticLabel = 'sellix'});

  final double size;
  final SxLogoSurface surface;
  final String semanticLabel;

  /// The cut colour of the prototype's `ctx-photo`, which has no palette role.
  static const _photoCut = Color(0xFF22322E);

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final Widget art;
    if (Theme.of(context).brightness == Brightness.dark) {
      art = SvgPicture.asset('assets/icons/logo_tile.svg', width: size, height: size);
    } else {
      final (Color fg, Color cut) = switch (surface) {
        SxLogoSurface.page => (p.anchor, p.page),
        SxLogoSurface.card => (p.anchor, p.card),
        SxLogoSurface.anchor => (p.onAnchor, p.anchor),
        SxLogoSurface.photo => (p.onAnchor, _photoCut),
      };
      art = SvgPicture.asset(
        'assets/icons/logo_glyph.svg',
        width: size,
        height: size,
        colorMapper: _GlyphColors(fg.toARGB32(), cut.toARGB32()),
      );
    }
    return Semantics(label: semanticLabel, image: true, child: ExcludeSemantics(child: art));
  }
}

/// logo_glyph.svg is drawn with fg #FFFFFF and cut #1C3A36; these are swapped at parse time.
/// Holds ints because flutter_svg sends the mapper to a background isolate and uses it in its cache key.
@immutable
class _GlyphColors extends ColorMapper {
  const _GlyphColors(this.fg, this.cut);

  final int fg;
  final int cut;

  static const _fgKey = 0xFFFFFFFF;
  static const _cutKey = 0xFF1C3A36;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) {
    final v = color.toARGB32();
    if (v == _fgKey) return Color(fg);
    if (v == _cutKey) return Color(cut);
    return color;
  }

  @override
  bool operator ==(Object other) => other is _GlyphColors && other.fg == fg && other.cut == cut;

  @override
  int get hashCode => Object.hash(fg, cut);
}
