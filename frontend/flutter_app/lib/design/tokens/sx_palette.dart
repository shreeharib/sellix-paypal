import 'package:flutter/material.dart';

@immutable
class SxPalette extends ThemeExtension<SxPalette> {
  const SxPalette({
    required this.page,
    required this.card,
    required this.tile,
    required this.line,
    required this.lineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.noteText,
    required this.skeleton,
    required this.scrim,
    required this.anchor,
    required this.onAnchor,
    required this.onAnchorSecondary,
    required this.anchorRaised,
    required this.anchorLine,
    required this.primary,
    required this.onPrimary,
    required this.primaryPressed,
    required this.signal,
    required this.onSignal,
    required this.signalOnAnchor,
    required this.livePill,
    required this.onLivePill,
    required this.attention,
    required this.onAttention,
    required this.attentionSoft,
    required this.attentionLine,
    required this.attentionText,
    required this.attentionTextStrong,
    required this.attentionTint,
    required this.attentionOnAnchor,
    required this.success,
    required this.successSoft,
    required this.successText,
    required this.error,
    required this.onError,
    required this.errorSoft,
    required this.errorText,
    required this.nav,
    required this.navIcon,
    required this.navActive,
    required this.onNavActive,
    required this.bubbleCustomer,
    required this.bubbleAi,
    required this.onBubbleAi,
    required this.sendIcon,
    required this.waveActive,
    required this.waveSilent,
    required this.floatingBorder,
    required this.floatingShadow,
  });

  final Color page, card, tile, line, lineStrong;
  final Color textPrimary, textSecondary, textTertiary, noteText, skeleton, scrim;
  final Color anchor, onAnchor, onAnchorSecondary, anchorRaised, anchorLine;
  final Color primary, onPrimary, primaryPressed;
  final Color signal, onSignal, signalOnAnchor, livePill, onLivePill;
  final Color attention, onAttention, attentionSoft, attentionLine;
  final Color attentionText, attentionTextStrong, attentionTint, attentionOnAnchor;
  final Color success, successSoft, successText;
  final Color error, onError, errorSoft, errorText;
  final Color nav, navIcon, navActive, onNavActive;
  final Color bubbleCustomer, bubbleAi, onBubbleAi, sendIcon;
  final Color waveActive, waveSilent, floatingBorder, floatingShadow;

  static const light = SxPalette(
    page: Color(0xFFE6EEEB),
    card: Color(0xFFFFFFFF),
    tile: Color(0xFFF4EEE4),
    line: Color(0xFFDCE5E2),
    lineStrong: Color(0xFFCAD6D2),
    textPrimary: Color(0xFF10201D),
    textSecondary: Color(0xFF5C6D69),
    textTertiary: Color(0xFF8A9A96),
    noteText: Color(0xFF3E4F4B),
    skeleton: Color(0xFFDCE5E2),
    scrim: Color(0x6610201D),
    anchor: Color(0xFF1C3A36),
    onAnchor: Color(0xFFFFFFFF),
    onAnchorSecondary: Color(0xFF9DB3AE),
    anchorRaised: Color(0xFF2A4945),
    anchorLine: Color(0xFF32514C),
    primary: Color(0xFF1C3A36),
    onPrimary: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF2A4945),
    signal: Color(0xFF4CB06C),
    onSignal: Color(0xFF10201D),
    signalOnAnchor: Color(0xFFA6E0BA),
    livePill: Color(0xFFFFFFFF),
    onLivePill: Color(0xFF10201D),
    attention: Color(0xFFD8B57A),
    onAttention: Color(0xFF10201D),
    attentionSoft: Color(0xFFF5EDE0),
    attentionLine: Color(0xFFE7D7BC),
    attentionText: Color(0xFF6E5226),
    attentionTextStrong: Color(0xFF4F3A18),
    attentionTint: Color(0xFFEEDFC6),
    attentionOnAnchor: Color(0xFFE7C890),
    success: Color(0xFF4CB06C),
    successSoft: Color(0xFFDDEFE3),
    successText: Color(0xFF1F5A35),
    error: Color(0xFFB4534A),
    onError: Color(0xFFFFFFFF),
    errorSoft: Color(0xFFF6E4E1),
    errorText: Color(0xFF7A2E26),
    nav: Color(0xFF1C3A36),
    navIcon: Color(0xFF8FA6A1),
    navActive: Color(0xFFFFFFFF),
    onNavActive: Color(0xFF10201D),
    bubbleCustomer: Color(0xFFFFFFFF),
    bubbleAi: Color(0xFF1C3A36),
    onBubbleAi: Color(0xFFFFFFFF),
    sendIcon: Color(0xFF4CB06C),
    waveActive: Color(0xFF4CB06C),
    waveSilent: Color(0xFF4A6661),
    floatingBorder: Color(0x00000000),
    floatingShadow: Color(0x1F10201D),
  );

  static const dark = SxPalette(
    page: Color(0xFF12231F),
    card: Color(0xFF1C322E),
    tile: Color(0xFF263F3A),
    line: Color(0xFF2A433F),
    lineStrong: Color(0xFF35504B),
    textPrimary: Color(0xFFEAF1EE),
    textSecondary: Color(0xFFA3B7B2),
    textTertiary: Color(0xFF7A8F8A),
    noteText: Color(0xFFC9D6D2),
    skeleton: Color(0xFF263F3A),
    scrim: Color(0x99050B0A),
    anchor: Color(0xFFE3ECE9),
    onAnchor: Color(0xFF10201D),
    onAnchorSecondary: Color(0xFF5C6D69),
    anchorRaised: Color(0xFFFFFFFF),
    anchorLine: Color(0xFFC9D6D2),
    primary: Color(0xFFE3ECE9),
    onPrimary: Color(0xFF10201D),
    primaryPressed: Color(0xFFCBD8D4),
    signal: Color(0xFF4CB06C),
    onSignal: Color(0xFF10201D),
    signalOnAnchor: Color(0xFF276E40),
    livePill: Color(0xFFFFFFFF),
    onLivePill: Color(0xFF10201D),
    attention: Color(0xFFD8B57A),
    onAttention: Color(0xFF10201D),
    attentionSoft: Color(0xFF2F2A20),
    attentionLine: Color(0xFF4D412C),
    attentionText: Color(0xFFE8CC98),
    attentionTextStrong: Color(0xFFE2D3B6),
    attentionTint: Color(0xFF4A3F2C),
    attentionOnAnchor: Color(0xFF9A6F2A),
    success: Color(0xFF4CB06C),
    successSoft: Color(0xFF23402F),
    successText: Color(0xFFA6E0BA),
    error: Color(0xFFD9776B),
    onError: Color(0xFF10201D),
    errorSoft: Color(0xFF3A2523),
    errorText: Color(0xFFF0B8AF),
    nav: Color(0xFF213A35),
    navIcon: Color(0xFF8FA6A1),
    navActive: Color(0xFFE3ECE9),
    onNavActive: Color(0xFF10201D),
    bubbleCustomer: Color(0xFF1C322E),
    bubbleAi: Color(0xFFE3ECE9),
    onBubbleAi: Color(0xFF10201D),
    sendIcon: Color(0xFF1C3A36),
    waveActive: Color(0xFF1C3A36),
    waveSilent: Color(0xFFA9BAB6),
    floatingBorder: Color(0xFF2A433F),
    floatingShadow: Color(0x00000000),
  );

  // Theme changes do not animate (DESIGN.md 11, rule 4).
  @override
  SxPalette copyWith() => this;

  @override
  SxPalette lerp(covariant SxPalette? other, double t) =>
      (other == null || t < 0.5) ? this : other;
}

extension SxContext on BuildContext {
  SxPalette get sx => Theme.of(this).extension<SxPalette>()!;
}
