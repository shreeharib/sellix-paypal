import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellix_merchant/core/api/api_exception.dart';
import 'package:sellix_merchant/core/auth/auth_controller.dart';
import 'package:sellix_merchant/core/config.dart';
import 'package:sellix_merchant/core/providers.dart';

/// Also run with `--dart-define=DEV_ACCESS_TOKEN=x` to cover the dev sign-in branch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('with no define the dev sign-in is inert', () async {
    if (AppConfig.usesDevSignIn) {
      markTestSkipped('DEV_ACCESS_TOKEN is set');
      return;
    }
    expect(AppConfig.devAccessToken, isEmpty);
    final c = container();
    expect(await c.read(authControllerProvider.future), AuthStatus.signedOut);
    // No tokens: the interceptor refuses before anything reaches the network.
    await expectLater(
      c.read(sellixApiProvider).me(),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
    );
  });

  test('stored tokens mean signed in', () async {
    if (AppConfig.usesDevSignIn) {
      markTestSkipped('DEV_ACCESS_TOKEN is set');
      return;
    }
    FlutterSecureStorage.setMockInitialValues({'sellix.refresh_token': 'r'});
    expect(await container().read(authControllerProvider.future), AuthStatus.signedIn);
  });

  test('with the define the app is signed in, and signing out is local', () async {
    if (!AppConfig.usesDevSignIn) {
      markTestSkipped('DEV_ACCESS_TOKEN is not set');
      return;
    }
    final c = container();
    expect(await c.read(authControllerProvider.future), AuthStatus.signedIn);
    await c.read(authControllerProvider.notifier).signOut();
    expect(c.read(authControllerProvider).value, AuthStatus.signedOut);
  });
}
