import 'package:flutter/material.dart';
import 'tokens/sx_palette.dart';
import 'tokens/sx_text.dart';
import 'tokens/sx_layout.dart';

ThemeData buildSellixTheme(SxPalette p, Brightness b) {
  final scheme = ColorScheme(
    brightness: b,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.signal,
    onSecondary: p.onSignal,
    error: p.error,
    onError: p.onError,
    surface: p.card,
    onSurface: p.textPrimary,
    surfaceTint: Colors.transparent,
  );

  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(SxRadius.pill),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.page,
    fontFamily: 'Satoshi',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: SxText.textTheme.apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    ),
    iconTheme: IconThemeData(color: p.textPrimary, size: 20),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      hintStyle: SxText.body.copyWith(color: p.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      border: border(p.textPrimary, 0),
      enabledBorder: border(p.textPrimary, 0),
      focusedBorder: border(p.textPrimary, 1.5),
      errorBorder: border(p.error, 1.5),
      focusedErrorBorder: border(p.error, 1.5),
      errorStyle: SxText.caption.copyWith(color: p.errorText),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.anchor,
      contentTextStyle: SxText.bodyS.copyWith(color: p.onAnchor),
      actionTextColor: p.signalOnAnchor,
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      modalBarrierColor: p.scrim,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: p.lineStrong,
      dragHandleSize: const Size(36, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SxRadius.sheet)),
      ),
    ),
  );
}

final sellixLight = buildSellixTheme(SxPalette.light, Brightness.light);
final sellixDark = buildSellixTheme(SxPalette.dark, Brightness.dark);

/// Floating bar decoration (DESIGN.md 14.7). Only for the nav, the bottom CTA and the composer.
BoxDecoration sxFloating(SxPalette p, Color fill) => BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(SxRadius.pill),
      border: Border.all(color: p.floatingBorder),
      boxShadow: [
        BoxShadow(color: p.floatingShadow, blurRadius: 24, offset: const Offset(0, 8)),
      ],
    );
