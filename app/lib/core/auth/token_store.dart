import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/models.dart';

/// Keeps the session tokens in the platform's secure storage (Keystore on Android).
class TokenStore {
  TokenStore(this._storage);

  static const _access = 'sellix.access_token';
  static const _refresh = 'sellix.refresh_token';
  static const _expiresAt = 'sellix.access_expires_at';

  /// Refresh a little before the access token actually expires.
  static const _margin = Duration(seconds: 30);

  final FlutterSecureStorage _storage;

  Future<void> save(TokenPair pair) async {
    final expiresAt = DateTime.now().add(Duration(seconds: pair.expiresIn) - _margin);
    await _storage.write(key: _access, value: pair.accessToken);
    await _storage.write(key: _refresh, value: pair.refreshToken);
    await _storage.write(key: _expiresAt, value: expiresAt.toIso8601String());
  }

  Future<String?> refreshToken() => _storage.read(key: _refresh);

  /// The access token, or null when it's missing or about to expire.
  Future<String?> validAccessToken() async {
    final expiresAt = DateTime.tryParse(await _storage.read(key: _expiresAt) ?? '');
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) return null;
    return _storage.read(key: _access);
  }

  Future<void> clear() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _expiresAt);
  }
}
