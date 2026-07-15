import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_api.dart';
import 'tokens.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}

/// Owns the session. Primary login is native email/password (+ 2FA) via
/// [AuthApi]; WebView SSO capture feeds [signIn] as a fallback. Keeps the
/// 5-minute access token fresh by rotating through `/auth/refresh`.
class AuthController extends ChangeNotifier {
  AuthController({AuthApi? api, FlutterSecureStorage? storage})
      : _api = api ?? AuthApi(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'ebb_tokens_v1';

  final AuthApi _api;
  final FlutterSecureStorage _storage;

  Tokens? _tokens;
  Future<Tokens>? _refreshInFlight;

  bool get isAuthenticated => _tokens != null;
  String get language => _tokens?.language ?? 'en';

  // ---- Session lifecycle ----

  Future<bool> restore() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return false;
    try {
      _tokens = Tokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
      return true;
    } catch (_) {
      await _storage.delete(key: _storageKey);
      return false;
    }
  }

  Future<void> signOut() async {
    _tokens = null;
    _refreshInFlight = null;
    await _storage.delete(key: _storageKey);
    notifyListeners();
  }

  // ---- Native email/password login ----

  /// Returns a [SignInResult]: either signed in, or a 2FA challenge to finish
  /// with [confirmTwoFactor]. On success the session is established.
  Future<SignInResult> signInWithPassword(String username, String password,
      {bool rememberMe = true}) async {
    final result = await _api.signInWithPassword(
      username: username,
      password: password,
      rememberMe: rememberMe,
    );
    if (result.tokens != null) await _establish(result.tokens!);
    return result;
  }

  Future<void> requestTwoFactor(String ref, String type) =>
      _api.requestTwoFactor(ref: ref, type: type);

  Future<void> confirmTwoFactor(String ref, String pin, {bool rememberMe = true}) async {
    final tokens = await _api.confirmTwoFactor(ref: ref, pin: pin, rememberMe: rememberMe);
    await _establish(tokens);
  }

  Future<void> _establish(Tokens tokens) async {
    _tokens = tokens;
    await _persist();
    notifyListeners();
  }

  // ---- Access-token freshness ----

  Future<String> validAccessToken() async {
    final t = _tokens;
    if (t == null) throw AuthException('Not signed in');
    if (t.isExpired(skew: const Duration(seconds: 45))) {
      return (await _refresh()).accessToken;
    }
    return t.accessToken;
  }

  Future<String> forceRefresh() async => (await _refresh()).accessToken;

  Future<Tokens> _refresh() =>
      _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);

  Future<Tokens> _doRefresh() async {
    final t = _tokens;
    if (t == null) throw AuthException('Not signed in');
    try {
      final next = await _api.refresh(t.refreshToken, language: t.language);
      _tokens = next;
      await _persist();
      notifyListeners();
      return next;
    } on AuthApiException {
      // Refresh token expired / rejected → require a fresh sign-in.
      await signOut();
      throw AuthException('Session expired; please sign in again');
    }
  }

  Future<void> _persist() async =>
      _storage.write(key: _storageKey, value: jsonEncode(_tokens!.toJson()));
}
