import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum SxBrand { instagram, whatsapp, paypal, upi, messenger, facebook, google, apple }

/// Official coloured brand logo from assets/icons. Only Apple is monochrome and takes [color].
class SxBrandIcon extends StatelessWidget {
  const SxBrandIcon(this.brand, {super.key, this.size = 20, this.color});

  final SxBrand brand;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = brand == SxBrand.apple ? (color ?? IconTheme.of(context).color) : null;
    return SvgPicture.asset(
      'assets/icons/${brand.name}.svg',
      width: size,
      height: size,
      excludeFromSemantics: true,
      colorFilter: tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
