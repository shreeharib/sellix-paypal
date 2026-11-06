import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sx_skeleton.dart';
import 'sx_snack.dart';
import 'sx_states.dart';

/// Loading, empty, error and data for one [AsyncValue].
///
/// - First load: [loading], or an [SxSkeletonList].
/// - Failed with nothing to show: [SxErrorState] with [onRetry].
/// - Data: [builder], or [empty] when [isEmpty] says so.
/// - Reload: keeps showing the data. A failed reload says so in a snackbar instead of
///   passing off the old data as fresh.
class SxAsyncView<T> extends StatefulWidget {
  const SxAsyncView({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
    this.loading,
    this.isEmpty,
    this.empty,
    this.errorMessage,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final Widget? loading;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  /// Replaces the text from `sxErrorMessage`.
  final String? errorMessage;

  @override
  State<SxAsyncView<T>> createState() => _SxAsyncViewState<T>();
}

class _SxAsyncViewState<T> extends State<SxAsyncView<T>> {
  Object? _reported;

  @override
  void didUpdateWidget(SxAsyncView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final v = widget.value;
    if (v.hasValue && v.hasError && !v.isLoading && !identical(v.error, _reported)) {
      _reported = v.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSxSnack(context, widget.errorMessage ?? sxErrorMessage(v.error));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    if (v.hasValue) {
      final data = v.requireValue;
      if (widget.empty != null && (widget.isEmpty?.call(data) ?? false)) return widget.empty!;
      return widget.builder(context, data);
    }
    if (v.hasError && !v.isLoading) {
      return SxErrorState(error: v.error, message: widget.errorMessage, onRetry: widget.onRetry);
    }
    return widget.loading ?? const SxSkeletonList();
  }
}
