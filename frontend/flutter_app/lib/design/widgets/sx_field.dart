import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_sheet.dart';

/// Text field (DESIGN.md 9.19): 52 high pill, or a 24 radius area when [maxLines] > 1.
/// Focus: 1.5 px `textPrimary`. Error: 1.5 px `error` with [errorText] below.
/// On a sheet it switches to the `page` background by itself.
class SxField extends StatefulWidget {
  const SxField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefix,
    this.trailing,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.focusNode,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.onTile = false,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;

  /// Fixed text before the input, e.g. "₹" or "+91".
  final String? prefix;
  final Widget? trailing;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;

  /// `tile` background, for a field on a card.
  final bool onTile;
  final TextAlign textAlign;

  @override
  State<SxField> createState() => _SxFieldState();
}

class _SxFieldState extends State<SxField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final area = widget.maxLines > 1;
    final hasError = widget.errorText != null;
    final bg = widget.onTile ? p.tile : (SxSheetScope.isOnSheet(context) ? p.page : p.card);
    final radius = area ? SxRadius.card : SxRadius.pill;
    final borderColor = hasError ? p.error : (_focused ? p.textPrimary : bg);

    final input = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      keyboardType: widget.keyboardType ?? (area ? TextInputType.multiline : null),
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      minLines: widget.minLines ?? (area ? 3 : 1),
      maxLength: widget.maxLength,
      obscureText: widget.obscureText,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      textAlign: widget.textAlign,
      cursorColor: p.textPrimary,
      style: SxText.body.copyWith(color: p.textPrimary),
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        counterText: '',
        contentPadding: EdgeInsets.zero,
        hintText: widget.hint,
        hintStyle: SxText.body.copyWith(color: p.textTertiary),
      ),
    );

    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: SxMotion.fast,
        curve: SxMotion.curve,
        constraints: BoxConstraints(minHeight: area ? 94 : 52),
        padding: area
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
            : const EdgeInsets.symmetric(horizontal: SxSpace.s20, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: area ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            if (widget.prefix != null) ...[
              Text(widget.prefix!, style: SxText.bodyStrong.copyWith(color: p.textSecondary)),
              const SizedBox(width: 10),
            ],
            Expanded(child: input),
            if (widget.trailing != null) ...[const SizedBox(width: 10), widget.trailing!],
          ],
        ),
      ),
    );

    if (widget.label == null && !hasError) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.s4, 0, SxSpace.s4, SxSpace.s8),
            child: Text(widget.label!,
                style: SxText.caption.copyWith(color: p.textSecondary, fontWeight: FontWeight.w600)),
          ),
        field,
        if (hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(SxSpace.s20, 6, SxSpace.s20, 0),
            child: Text(widget.errorText!, style: SxText.caption.copyWith(color: p.errorText)),
          ),
      ],
    );
  }
}
