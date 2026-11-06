import 'package:flutter/material.dart';

import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_button.dart';
import 'sx_snack.dart';

/// Tells fields, chips and cards they sit on a sheet, so they switch to the `page` background.
class SxSheetScope extends InheritedWidget {
  const SxSheetScope({super.key, required super.child});

  static bool isOnSheet(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SxSheetScope>() != null;

  @override
  bool updateShouldNotify(SxSheetScope oldWidget) => false;
}

/// Bottom sheet (DESIGN.md 9.20, prototype `sheet()`): 36 x 4 drag handle, `scrim`, drag or tap
/// the scrim to dismiss, max height 88%, rises above the keyboard. Pop with
/// `Navigator.of(context).pop(result)` using the builder's context.
///
/// The body scrolls when it is tall, so build a `Column`, not a `ListView`
/// (pass `scrollable: false` if the body scrolls by itself).
Future<T?> showSxSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  bool isDismissible = true,
  bool scrollable = true,
}) {
  hideSxSnack();
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    showDragHandle: false,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(),
    sheetAnimationStyle: const AnimationStyle(
      duration: SxMotion.slow,
      reverseDuration: SxMotion.slow,
      curve: SxMotion.curve,
      reverseCurve: SxMotion.curve,
    ),
    builder: (sheetContext) => _SxSheetFrame(
      title: title,
      subtitle: subtitle,
      scrollable: scrollable,
      child: Builder(builder: builder),
    ),
  );
}

class _SxSheetFrame extends StatefulWidget {
  const _SxSheetFrame({required this.child, required this.scrollable, this.title, this.subtitle});

  final Widget child;
  final bool scrollable;
  final String? title;
  final String? subtitle;

  @override
  State<_SxSheetFrame> createState() => _SxSheetFrameState();
}

class _SxSheetFrameState extends State<_SxSheetFrame> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    SxSnackHost.openSheetKey = _key;
  }

  @override
  void dispose() {
    if (SxSnackHost.openSheetKey == _key) SxSnackHost.openSheetKey = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    final mq = MediaQuery.of(context);
    final safe = mq.viewPadding.bottom;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) Text(widget.title!, style: SxText.titleM.copyWith(color: p.textPrimary)),
        if (widget.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: SxSpace.s4),
            child: Text(widget.subtitle!, style: SxText.bodyS.copyWith(color: p.textSecondary)),
          ),
        if (widget.title != null || widget.subtitle != null) const SizedBox(height: SxSpace.s16),
        widget.scrollable ? widget.child : Flexible(child: widget.child),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SxSheetScope(
        child: Container(
          key: _key,
          constraints: BoxConstraints(maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.88),
          width: double.infinity,
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(SxRadius.sheet)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: p.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    SxSpace.screen,
                    0,
                    SxSpace.screen,
                    mq.viewInsets.bottom > 0 ? SxSpace.s16 : (safe > SxSpace.s20 ? safe : SxSpace.s20) + 14,
                  ),
                  child: widget.scrollable ? SingleChildScrollView(child: body) : body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmation sheet for anything that sends, refunds or changes status.
/// Resolves to true only when the merchant taps [confirmLabel].
Future<bool> showSxConfirm(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? body,
  String cancelLabel = 'Cancel',
  IconData? confirmIcon,
}) async {
  final result = await showSxSheet<bool>(
    context,
    title: title,
    subtitle: body,
    builder: (sheet) => SxButtonRow(
      children: [
        SxButton(
          label: cancelLabel,
          kind: SxButtonKind.secondary,
          onTap: () => Navigator.of(sheet).pop(false),
        ),
        SxButton(
          label: confirmLabel,
          icon: confirmIcon,
          onTap: () => Navigator.of(sheet).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
