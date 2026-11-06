import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../providers.dart';
import 'auth_controller.dart';

/// What a connect from inside the app came to.
enum InstagramConnectOutcome {
  /// This shop's Instagram works now.
  connected,

  /// The account belongs to another shop, which is now the signed-in one.
  otherShop,

  /// Signed in, but the shop's Instagram still does not work.
  notConnected,

  /// The merchant closed Instagram's page.
  cancelled,

  /// The login or the API failed: [InstagramConnectResult.error] says why.
  failed,
}

class InstagramConnectResult {
  const InstagramConnectResult(this.outcome, {this.me, this.error});

  final InstagramConnectOutcome outcome;

  /// The shop as it is now, when the API answered.
  final Me? me;
  final Object? error;
}

/// Connects or reconnects Instagram for a shop that is already signed in (onboarding, Channels),
/// including the DEV ONLY `DEV_ACCESS_TOKEN` session.
///
/// The API's only Instagram flow for the app is "Continue with Instagram": the operator's connect
/// link (`connect-instagram`) is a CLI tool, not an endpoint. Instagram's login signs the same
/// account into the same shop and renews its connection; a different account signs in to that
/// account's shop. So this runs the real login, then reads back who came back rather than assuming.
class InstagramConnect {
  InstagramConnect(this._ref);

  final Ref _ref;

  Future<InstagramConnectResult> run({required String merchantId}) async {
    try {
      await _ref.read(authControllerProvider.notifier).signInWithInstagram();
    } on SignInCancelled {
      return const InstagramConnectResult(InstagramConnectOutcome.cancelled);
    } catch (error) {
      return InstagramConnectResult(InstagramConnectOutcome.failed, error: error);
    }
    final Me me;
    try {
      // Read after the sign-in, so it goes out with the new session.
      me = await _ref.read(sellixApiProvider).me();
    } catch (error) {
      return InstagramConnectResult(InstagramConnectOutcome.failed, error: error);
    }
    if (me.merchant.id != merchantId) return InstagramConnectResult(InstagramConnectOutcome.otherShop, me: me);
    final instagram = me.channels.where((c) => c.channel == 'instagram').firstOrNull;
    final expires = instagram?.tokenExpiresAt;
    final works = instagram?.status == 'active' && (expires == null || expires.isAfter(DateTime.now()));
    return InstagramConnectResult(works ? InstagramConnectOutcome.connected : InstagramConnectOutcome.notConnected, me: me);
  }
}

final instagramConnectProvider = Provider<InstagramConnect>(InstagramConnect.new);
