import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/sx_layout.dart';

/// Every tappable area in the app. Scale 0.98 in 120 ms, no splash (0.94 with [small]).
/// A null [onTap] makes it inert and dims nothing: the caller shows the reason.
class SxPressable extends StatefulWidget {
  const SxPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.haptic = true,
    this.small = false,
    this.onDownChanged,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool haptic;

  /// Small controls (icon buttons, chips) press deeper, like the prototype's `data-small`.
  final bool small;
  final ValueChanged<bool>? onDownChanged;

  @override
  State<SxPressable> createState() => _SxPressableState();
}

class _SxPressableState extends State<SxPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onDownChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap == null ? null : (_) => _set(true),
        onTapUp: onTap == null ? null : (_) => _set(false),
        onTapCancel: onTap == null ? null : () => _set(false),
        onTap: onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.lightImpact();
                onTap();
              },
        child: AnimatedScale(
          scale: _down ? (widget.small ? 0.94 : 0.98) : 1,
          duration: SxMotion.fast,
          curve: SxMotion.curve,
          child: widget.child,
        ),
      ),
    );
  }
}
