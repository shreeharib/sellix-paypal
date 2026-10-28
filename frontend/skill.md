---
name: sellix-flutter-ui
description: Build, change or review Flutter screens and widgets for the sellix merchant app with the Forest design system (light and dark themes). Use for every sellix UI, theme, widget or design review task.
---

# sellix Flutter UI skill

## Purpose

Use this skill to make sellix merchant app UI that obeys the Forest design system in light and dark themes.
DESIGN.md is in the same folder as this file. DESIGN.md is the source of truth.
If this file and DESIGN.md do not agree, obey DESIGN.md.

## Before you start

1. Read DESIGN.md completely.
2. Find the screen template in DESIGN.md section 10.3.
3. Find the components in DESIGN.md section 9.
4. Examine `lib/design/` for widgets that exist. Use them before you make new ones.

## Project structure

```
lib/design/
  tokens/
    sx_palette.dart     (SxPalette light and dark, context.sx)
    sx_text.dart
    sx_layout.dart      (SxSpace, SxRadius, SxMotion)
  sx_theme.dart         (sellixLight, sellixDark, sxFloating)
  widgets/
    sx_pressable.dart
    sx_button.dart
    sx_chip.dart
    sx_avatar.dart
    sx_header.dart
    sx_hero_card.dart
    sx_section_header.dart
    sx_row_card.dart
    sx_needs_you_card.dart
    sx_ai_note.dart
    sx_bubble.dart
    sx_escalation_card.dart
    sx_composer.dart
    sx_voice_card.dart
    sx_stock_row.dart
    sx_floating_nav.dart
    sx_bottom_cta.dart
lib/features/<feature>/   (screens use only lib/design widgets and tokens)
```

## How to read colors

Read all colors from the palette by role:

```dart
final p = context.sx;
Text('Today\'s sales', style: SxText.caption.copyWith(color: p.onAnchorSecondary));
```

Do not use `Colors.white`, `Colors.black` or hex values in feature code or widgets.
The palette gives the correct value for the active theme.

## Procedure: make a new screen

1. Identify the one job of the screen. Write it as one sentence.
2. Identify the one primary action. Put it in a bottom CTA or in the floating navigation flow.
3. Select the screen type:
   - Root tab screen: show the floating navigation bar. Do not show a bottom CTA.
   - Task screen: hide the navigation bar. Show a bottom CTA or a composer.
4. Use the scaffold pattern below.
5. Build the content from top to bottom in the order of the template in DESIGN.md 10.3.
6. Use only `context.sx`, `SxText`, `SxSpace`, `SxRadius` and `SxMotion`.
7. Add loading, empty and error states (DESIGN.md 9.22).
8. Run the screen in the light theme and in the dark theme.
9. Do the review checklist at the end of this file.

### Scaffold pattern

```dart
class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: p.page,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: ListView(
                padding: EdgeInsets.only(bottom: SxSpace.bottomInset + bottomSafe),
                children: const [
                  // Header, anchor block, cards, sections.
                ],
              ),
            ),
            Positioned(
              left: SxSpace.screen,
              right: SxSpace.screen,
              bottom: bottomSafe + SxSpace.navGap,
              child: const SizedBox.shrink(), // SxFloatingNav or SxBottomCta.
            ),
          ],
        ),
      ),
    );
  }
}
```

## Procedure: make a new component

1. Make sure that no component in DESIGN.md section 9 does the same job.
2. If a component does the same job, use it or add a variant to it.
3. Name the widget with the prefix `Sx`.
4. Read colors from `context.sx`. Do not write hex values or numbers that are not in the token files.
5. If the component needs a new color role, add the role to `SxPalette` with a light value and a dark value. Add it to DESIGN.md section 3.
6. Wrap tappable areas in `SxPressable`.
7. Make the tap target minimum 44 × 44.
8. Add a `Semantics` label to icon-only controls.
9. Add the component specification to DESIGN.md section 9.

### Reference: SxPressable

```dart
class SxPressable extends StatefulWidget {
  const SxPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;
  final bool haptic;

  @override
  State<SxPressable> createState() => _SxPressableState();
}

class _SxPressableState extends State<SxPressable> {
  bool _down = false;

  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () {
          if (widget.haptic) HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: SxMotion.fast,
          curve: SxMotion.curve,
          child: widget.child,
        ),
      ),
    );
  }
}
```

### Reference: SxButton

```dart
enum SxButtonKind { primary, secondary, signal }

class SxButton extends StatelessWidget {
  const SxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = SxButtonKind.primary,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final SxButtonKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final (bg, fg, border) = switch (kind) {
      SxButtonKind.primary => (p.primary, p.onPrimary, null),
      SxButtonKind.secondary =>
        (Colors.transparent, p.textPrimary, Border.all(color: p.lineStrong)),
      // Signal is for anchor surfaces only.
      SxButtonKind.signal => (p.signal, p.onSignal, null),
    };
    final height = kind == SxButtonKind.signal ? 36.0 : 44.0;

    return SxPressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(SxRadius.pill),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: SxSpace.s8),
            ],
            Text(label, style: SxText.label.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
```

### Reference: SxBottomCta

```dart
class SxBottomCta extends StatelessWidget {
  const SxBottomCta({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return SxPressable(
      haptic: false,
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.only(left: 26, right: 6),
        decoration: sxFloating(p, p.primary),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: SxText.labelL.copyWith(color: p.onPrimary)),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: p.signal, shape: BoxShape.circle),
              child: Icon(Icons.arrow_forward, size: 20, color: p.onSignal),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Reference: SxLivePill

```dart
class SxLivePill extends StatelessWidget {
  const SxLivePill({super.key, required this.label, required this.dot});

  final String label;
  final Color dot; // p.signal, p.attention or p.textTertiary.

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.livePill,
        borderRadius: BorderRadius.circular(SxRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: SxText.micro.copyWith(color: p.onLivePill)),
        ],
      ),
    );
  }
}
```

## Hard rules

1. Do not write hex colors, `Colors.white` or `Colors.black` in feature code or widgets. Use `context.sx`.
2. Every new color role has a light value and a dark value.
3. Do not write `TextStyle(...)` in feature code. Use `SxText` and `copyWith(color: ...)` only.
4. Use `signal` green only for sellix activity. Use it as a fill or dot. For green text, use `signalOnAnchor` on anchor surfaces.
5. Use the attention family only for items that the merchant must act on.
6. Put `onAttention` text on `attention` fills.
7. The agent status pill is always `livePill` with a colored dot.
8. Use one primary button or bottom CTA in each view.
9. Do not show the floating navigation bar and a bottom CTA together.
10. Do not use shadows on cards. Use `sxFloating` only on floating bars.
11. Do not use font weights other than 500, 600 and 700.
12. Do not use text smaller than 12 px.
13. Keep 20 px screen margins.
14. Do not use disabled buttons. Show the reason after a tap.
15. Show customer messages exactly as written.
16. Use sentence case in all UI text.

## Copy rules

1. Button labels start with a verb and have one to four words.
2. System text does not say "I." sellix says "I" only in AI notes, escalation cards and AI bubbles.
3. sellix says what it did, then why.
4. Do not use "please," "successfully" or exclamation marks in system text.
5. Errors say what happened, then what to do.
6. Use short, simple words.

## Review checklist

Do these checks before you finish a screen or component:

- [ ] The screen has one job and one primary action.
- [ ] All colors come from `context.sx`.
- [ ] All text styles come from `SxText`.
- [ ] All spacing and radii come from `SxSpace` and `SxRadius`.
- [ ] The screen looks correct in the light theme.
- [ ] The screen looks correct in the dark theme.
- [ ] The anchor block is forest green in light and mint in dark.
- [ ] Signal green shows only sellix activity.
- [ ] Sand shows only items that need the merchant.
- [ ] No card has a shadow.
- [ ] Screen margins are 20 px.
- [ ] Scroll content has bottom padding of `SxSpace.bottomInset` plus the safe area.
- [ ] The status bar icons have the correct color for the theme.
- [ ] Tap targets are minimum 44 × 44.
- [ ] Icon-only controls have semantic labels.
- [ ] States do not use color only.
- [ ] The screen works at text scale 1.3.
- [ ] Tamil and Devanagari text shows correctly in chat bubbles.
- [ ] Loading, empty and error states exist.
- [ ] Animations stop when "reduce motion" is on.

## Common mistakes

| Mistake | Correct action |
|---|---|
| White text on the hero card in code | Use `p.onAnchor`. White fails on the mint anchor in dark theme |
| Green text on a card | Use `signalOnAnchor` on anchor only. On cards, use a green dot and normal text |
| Sand chip for "Waiting payment" | Use a neutral chip. The customer must act, not the merchant |
| Shadow on a floating bar in dark theme | Use `sxFloating`. It gives a border in dark and a shadow in light |
| Heavy weight on every label | Use 600 for labels and 700 only for titles and numbers |
| Two anchor cards on one screen | Change one to a `card` |
| Text scale breaks the hero card | Clamp the display style at 1.2 with `TextScaler.clamp` |
| Tamil text shows as boxes | Add the Noto fallback fonts to `fontFamilyFallback` |
| Navigation bar covers the last card | Add `SxSpace.bottomInset` bottom padding |