import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the sign-in screens tell each other: a sign-in the merchant asked for (the connecting
/// screen runs it, as the router leaves that screen alone once signed in) and why the last failed.
class SignInFlowState {
  const SignInFlowState({this.requested = false, this.error});

  final bool requested;
  final String? error;
}

class SignInFlow extends Notifier<SignInFlowState> {
  @override
  SignInFlowState build() => const SignInFlowState();

  void request() => state = const SignInFlowState(requested: true);

  /// True once per request, so the connecting screen starts one browser session only.
  bool takeRequest() {
    final was = state.requested;
    if (was) state = SignInFlowState(error: state.error);
    return was;
  }

  void failed(String message) => state = SignInFlowState(error: message);
}

final signInFlowProvider = NotifierProvider<SignInFlow, SignInFlowState>(SignInFlow.new);
