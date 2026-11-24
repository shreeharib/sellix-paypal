/// Local notifications (no push server yet): shown by the app itself while it is alive, also in
/// the background until Android stops it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app needs from the phone's notifications. Tests use a fake.
abstract interface class LocalNotifier {
  /// Sets up the channel. [onTap] gets the route of a notification the merchant tapped.
  Future<void> init({required void Function(String route) onTap});

  /// Android 13+: asks for POST_NOTIFICATIONS. True when notifications may be shown.
  Future<bool> requestPermission();

  Future<void> show({required int id, required String title, required String body, required String route});

  /// The route of the notification that started the app, if one did.
  Future<String?> launchRoute();
}

/// flutter_local_notifications on Android. Elsewhere (web, desktop, tests) it does nothing.
class PluginNotifier implements LocalNotifier {
  /// Set once [init] has run on Android.
  FlutterLocalNotificationsPlugin? _plugin;

  static const _channel = AndroidNotificationDetails(
    'sellix_alerts',
    'Questions and paid orders',
    channelDescription: 'When sellix needs your answer, and when a customer pays.',
    importance: Importance.high,
    priority: Priority.high,
  );

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> init({required void Function(String route) onTap}) async {
    if (!_supported || _plugin != null) return;
    final plugin = FlutterLocalNotificationsPlugin();
    try {
      await plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (response) {
          final route = response.payload;
          if (route != null && route.isNotEmpty) onTap(route);
        },
      );
      _plugin = plugin;
    } on Object catch (error) {
      debugPrint('sellix: notifications are not available: $error');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    // Asking needs no channel set up, so this works before init (at the end of onboarding).
    final android = (_plugin ?? FlutterLocalNotificationsPlugin())
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    try {
      // Null below Android 13, where no permission is needed.
      return await android.requestNotificationsPermission() ?? true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> show({required int id, required String title, required String body, required String route}) async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
        payload: route,
      );
    } on Object catch (error) {
      debugPrint('sellix: a notification could not be shown: $error');
    }
  }

  @override
  Future<String?> launchRoute() async {
    try {
      final details = await _plugin?.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload;
    } on Object {
      return null;
    }
  }
}

final localNotifierProvider = Provider<LocalNotifier>((ref) => PluginNotifier());

/// Whether the app polls and notifies. main() turns it on; widget tests that boot the whole app
/// leave it off, so no timer or plugin runs unless a test asks for it.
final notificationsEnabledProvider = Provider<bool>((ref) => false);
