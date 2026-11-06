import 'package:flutter/material.dart';

abstract final class SxText {
  static const _f = 'Satoshi';
  static const _fb = ['NotoSansTamil', 'NotoSansDevanagari'];
  static const _tnum = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 40, height: 44 / 40, letterSpacing: -1.5,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
    fontFeatures: _tnum,
  );
  static const titleL = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 30, height: 34 / 30, letterSpacing: -1.0,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
  );
  static const titleM = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 18, height: 24 / 18, letterSpacing: -0.3,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
  );
  static const stat = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 20, height: 24 / 20, letterSpacing: -0.3,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
    fontFeatures: _tnum,
  );
  static const counter = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 17, height: 20 / 17,
    fontWeight: FontWeight.w700, fontVariations: [FontVariation('wght', 700)],
    fontFeatures: _tnum,
  );
  static const labelL = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 16, height: 20 / 16,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );
  static const bodyStrong = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 15, height: 22 / 15, letterSpacing: -0.1,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );
  static const body = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 15, height: 22 / 15, letterSpacing: -0.1,
    fontWeight: FontWeight.w500, fontVariations: [FontVariation('wght', 500)],
  );
  static const label = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 14, height: 20 / 14,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );
  static const bodyS = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 14, height: 20 / 14,
    fontWeight: FontWeight.w500, fontVariations: [FontVariation('wght', 500)],
  );
  static const caption = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 13, height: 18 / 13,
    fontWeight: FontWeight.w500, fontVariations: [FontVariation('wght', 500)],
  );
  static const micro = TextStyle(
    fontFamily: _f, fontFamilyFallback: _fb,
    fontSize: 12, height: 16 / 12,
    fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)],
  );

  static const textTheme = TextTheme(
    displayLarge: display,
    headlineMedium: titleL,
    titleMedium: titleM,
    bodyLarge: body,
    bodyMedium: bodyS,
    bodySmall: caption,
    labelLarge: label,
    labelSmall: micro,
  );
}
