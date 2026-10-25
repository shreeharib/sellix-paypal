import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636): proves that the app redeeming a login code is the one that started it.
class Pkce {
  Pkce._(this.verifier) : challenge = _challengeFor(verifier);

  /// A fresh random verifier (64 characters, from a cryptographically secure source).
  factory Pkce.generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    return Pkce._(base64UrlEncode(bytes).replaceAll('=', ''));
  }

  final String verifier;
  final String challenge;

  static String _challengeFor(String verifier) =>
      base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
}
