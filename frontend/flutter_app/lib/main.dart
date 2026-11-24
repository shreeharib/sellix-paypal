import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/notifications/local_notifier.dart';
import 'core/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      // Every screen has its own retry button, so a failure shows at once
      // instead of hiding behind Riverpod's silent retries.
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The real app polls and notifies; tests that boot the whole app leave it off.
        notificationsEnabledProvider.overrideWithValue(true),
      ],
      child: const SellixApp(),
    ),
  );
}
