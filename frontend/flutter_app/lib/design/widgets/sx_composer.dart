import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../sx_theme.dart';
import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_motion.dart';
import 'sx_pressable.dart';

/// DESIGN.md 9.14. Put it in `SxScaffold(floating: ...)` so it floats above the safe area.
class SxComposer extends StatefulWidget {
  const SxComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSend,
    this.onAttach,
    this.attachIcon,
    this.attachLabel = 'Attach',
    this.onChanged,
    this.focusNode,
    this.sending = false,
    this.enabled = true,
  });

  final TextEditingController controller;

  /// "Reply as {merchant name}".
  final String hint;
  final VoidCallback? onSend;
  final VoidCallback? onAttach;
  final IconData? attachIcon;
  final String attachLabel;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool sending;
  final bool enabled;

  @override
  State<SxComposer> createState() => _SxComposerState();
}

class _SxComposerState extends State<SxComposer> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Focus(
            onFocusChange: (v) => setState(() => _focused = v),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: EdgeInsets.only(left: widget.onAttach == null ? SxSpace.s20 : SxSpace.s8, right: SxSpace.s8),
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: p.textPrimary, width: 1.5),
                    )
                  : null,
              decoration: sxFloating(p, p.card).copyWith(borderRadius: BorderRadius.circular(26)),
              child: Row(
                children: [
                  if (widget.onAttach != null)
                    SxPressable(
                      small: true,
                      onTap: widget.onAttach,
                      semanticLabel: widget.attachLabel,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(widget.attachIcon ?? TablerIcons.paperclip, size: 20, color: p.textSecondary),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        enabled: widget.enabled,
                        onChanged: widget.onChanged,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: SxText.body.copyWith(color: p.textPrimary),
                        cursorColor: p.textPrimary,
                        decoration: InputDecoration.collapsed(
                          hintText: widget.hint,
                          hintStyle: SxText.body.copyWith(color: p.textTertiary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: SxSpace.s8),
        SxPressable(
          small: true,
          onTap: widget.sending ? null : widget.onSend,
          semanticLabel: 'Send',
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: p.primary,
              shape: BoxShape.circle,
              border: Border.all(color: p.floatingBorder),
              boxShadow: [BoxShadow(color: p.floatingShadow, blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: widget.sending
                ? SxSpin(child: Icon(TablerIcons.loader_2, size: 20, color: p.sendIcon))
                : Icon(TablerIcons.send, size: 20, color: p.sendIcon),
          ),
        ),
      ],
    );
  }
}
