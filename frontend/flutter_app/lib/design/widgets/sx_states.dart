import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../tokens/sx_layout.dart';
import '../tokens/sx_palette.dart';
import '../tokens/sx_text.dart';
import 'sx_button.dart';
import 'sx_surfaces.dart';

/// The text to show for a failure: an API message is safe to show; anything else is not.
String sxErrorMessage(Object? error) =>
    error is ApiException ? error.message : 'Something went wrong. Please try again.';

/// DESIGN.md 9.22: icon tile, inviting headline, one line, one primary button.
class SxEmptyState extends StatelessWidget {
  const SxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Replaces the button built from [actionLabel].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.sx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: SxSpace.s40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SxIconTile(icon: icon),
            const SizedBox(height: SxSpace.s16),
            Text(title, textAlign: TextAlign.center, style: SxText.titleM.copyWith(color: p.textPrimary)),
            if (body != null) ...[
              const SizedBox(height: SxSpace.s8),
              Text(body!, textAlign: TextAlign.center, style: SxText.bodyS.copyWith(color: p.textSecondary)),
            ],
            if (action != null) ...[
              const SizedBox(height: SxSpace.s16),
              action!,
            ] else if (actionLabel != null) ...[
              const SizedBox(height: SxSpace.s16),
              SxButton(label: actionLabel!, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// DESIGN.md 9.22: `errorSoft` banner that says what happened, with a retry.
class SxErrorState extends StatelessWidget {
  const SxErrorState({super.key, this.error, this.message, this.onRetry, this.retryLabel = 'Try again'});

  /// Turned into text with [sxErrorMessage], unless [message] is given.
  final Object? error;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SxSpace.screen),
      child: Center(
        child: SxBanner(
          tone: SxBannerTone.error,
          message: message ?? sxErrorMessage(error),
          action: onRetry == null
              ? null
              : SxLinkButton(label: retryLabel, onTap: onRetry, color: context.sx.errorText),
        ),
      ),
    );
  }
}
