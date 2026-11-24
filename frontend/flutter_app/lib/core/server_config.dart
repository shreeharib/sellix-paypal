/// Which sellix server the app talks to. The build's `API_BASE_URL` is the default; the merchant (or
/// whoever sets the phone up) can point the app at another one from the sign-in screen or Profile.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'theme_mode.dart';

/// A server address without a trailing slash, e.g. `https://api.example.com`.
class ServerUrl extends Notifier<String> {
  static const _key = 'server_url';

  @override
  String build() {
    final saved = _prefsOrNull()?.getString(_key);
    return (saved == null || saved.isEmpty) ? normalizeServerUrl(AppConfig.apiBaseUrl) : saved;
  }

  /// The build's default address.
  String get buildDefault => normalizeServerUrl(AppConfig.apiBaseUrl);

  /// Saves [url] (already checked with [serverUrlError]). Screens use
  /// `AuthController.changeServer`, which also signs the merchant out.
  Future<void> set(String url) async {
    final next = normalizeServerUrl(url);
    state = next;
    final prefs = _prefsOrNull();
    if (prefs == null) return;
    if (next == buildDefault) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, next);
    }
  }

  /// Tests and tools that build a bare container have no preferences: the default applies.
  SharedPreferences? _prefsOrNull() {
    try {
      return ref.read(sharedPreferencesProvider);
    } on Object {
      return null;
    }
  }
}

final serverUrlProvider = NotifierProvider<ServerUrl, String>(ServerUrl.new);

/// Trimmed, with no trailing slash.
String normalizeServerUrl(String url) {
  var text = url.trim();
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// Why [url] can't be used, in plain words, or null when it's fine. Release builds need https:
/// the session tokens travel with every request.
String? serverUrlError(String url, {bool release = kReleaseMode}) {
  final text = normalizeServerUrl(url);
  if (text.isEmpty) return 'Enter the server address.';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'That is not a web address. It looks like https://api.yourshop.com';
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    return 'The address starts with https://';
  }
  if (release && uri.scheme != 'https') return 'Use an https:// address.';
  if (uri.hasQuery || uri.hasFragment) return 'Leave out anything after ? or #.';
  return null;
}

/// Asks [url]'s `GET /health` whether a sellix server answers there.
typedef ServerCheck = Future<bool> Function(String url);

Future<bool> _checkHealth(String url) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  try {
    final response = await dio.get<Object?>('${normalizeServerUrl(url)}/health');
    final data = response.data;
    return response.statusCode == 200 && data is Map && data['status'] == 'ok';
  } on Object {
    return false;
  } finally {
    dio.close(force: true);
  }
}

/// Tests replace it so no request leaves the machine.
final serverCheckProvider = Provider<ServerCheck>((ref) => _checkHealth);
