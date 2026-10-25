import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';

/// Whether the signed-in merchant has finished the guided setup. A new shop (first
/// "Continue with Instagram") hasn't, so the router sends it to onboarding.
class OnboardingStatus extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    if (ref.watch(authControllerProvider).value != AuthStatus.signedIn) return true;
    final me = await ref.read(sellixApiProvider).me();
    return me.onboardingCompleted;
  }

  void completed() => state = const AsyncData(true);
}

final onboardingStatusProvider =
    AsyncNotifierProvider<OnboardingStatus, bool>(OnboardingStatus.new);
