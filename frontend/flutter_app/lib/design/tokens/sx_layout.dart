import 'package:flutter/animation.dart';

abstract final class SxSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
  static const s48 = 48.0;

  static const screen = 20.0;
  static const card = 16.0;
  static const hero = 20.0;
  static const listGap = 8.0;
  static const stackGap = 12.0;
  static const sectionTop = 24.0;
  static const sectionBottom = 12.0;
  static const headerHeight = 64.0;
  static const navHeight = 64.0;
  static const navGap = 12.0;
  static const bottomInset = 112.0;
}

abstract final class SxRadius {
  static const tail = 6.0;
  static const tile = 14.0;
  static const attach = 18.0;
  static const bubble = 20.0;
  static const card = 24.0;
  static const hero = 28.0;
  static const sheet = 32.0;
  static const pill = 999.0;
}

abstract final class SxMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const nav = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const pulse = Duration(milliseconds: 1600);
  static const stagger = Duration(milliseconds: 40);
  static const curve = Curves.easeOutCubic;
  static const move = Curves.easeInOutCubic;

  /// Small overshoot for toggles and checks (prototype --spring).
  static const spring = Cubic(0.34, 1.36, 0.64, 1);
}
