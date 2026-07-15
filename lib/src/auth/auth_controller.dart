import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
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
        _storage = storage ??
            const FlutterSecureStorage(
              // Encrypt at rest with the Android Keystore (not plain prefs),
              // and keep the token unreadable until first unlock on iOS.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  static const _storageKey = 'ebb_tokens_v1';

  final AuthApi _api;
  final FlutterSecureStorage _storage;

  Tokens? _tokens;
  Future<Tokens>? _refreshInFlight;

  bool get isAuthenticated => _tokens != null;
  String get language => _tokens?.language ?? 'en';

  // ---- Session lifecycle ----

  Future<bool> restore() async {
    _tokens = await _readStored();
    if (_tokens == null) return false;
    notifyListeners();
    return true;
  }

  Future<Tokens?> _readStored() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return null;
    try {
      return Tokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
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
    if (t.isExpired(skew: EbbConfig.refreshSkew)) {
      return (await _refresh()).accessToken;
    }
    return t.accessToken;
  }

  Future<String> forceRefresh() async => (await _refresh()).accessToken;

  Future<Tokens> _refresh() =>
      _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);

  Future<Tokens> _doRefresh() async {
    // Another isolate (the background monitor) may have rotated the token; prefer
    // the latest persisted copy so the UI and service don't invalidate each other.
    final current = await _readStored() ?? _tokens;
    if (current == null) throw AuthException('Not signed in');

    // If the persisted access token is already fresh, adopt it — no network call.
    if (!current.isExpired(skew: EbbConfig.refreshSkew)) {
      _tokens = current;
      return current;
    }
    try {
      final next = await _api.refresh(current.refreshToken, language: current.language);
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
