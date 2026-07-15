import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'tokens.dart';

class AuthApiException implements Exception {
  AuthApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'AuthApiException($statusCode): $message';
}

/// A 2FA challenge returned by /auth/sign-in when a one-time code is required.
class TwoFactorChallenge {
  const TwoFactorChallenge({
    required this.ref,
    this.primaryMethod,
    this.emailEnabled = false,
    this.smsEnabled = false,
    this.maskedEmail,
  });

  final String ref;
  final String? primaryMethod; // e.g. "EMAIL" | "SMS"
  final bool emailEnabled;
  final bool smsEnabled;
  final String? maskedEmail;

  factory TwoFactorChallenge.fromJson(Map<String, dynamic> j) => TwoFactorChallenge(
        ref: j['ref'] as String,
        primaryMethod: j['primaryTwoFactorAuthenticationMethod'] as String?,
        emailEnabled: (j['isEmailEnabled'] as bool?) ?? false,
        smsEnabled: (j['isSMSEnabled'] as bool?) ?? false,
        maskedEmail: j['email'] as String?,
      );
}

/// Result of a sign-in attempt: either tokens, or a 2FA challenge to complete.
class SignInResult {
  const SignInResult.success(this.tokens) : challenge = null;
  const SignInResult.twoFactor(this.challenge) : tokens = null;

  final Tokens? tokens;
  final TwoFactorChallenge? challenge;

  bool get needsTwoFactor => challenge != null;
}

/// Low-level EBB auth endpoints. All auth calls carry the constant
/// `ClientId: d0Vi` and `endpoint-version` the app uses.
class AuthApi {
  AuthApi({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Map<String, String> _authHeaders({bool longLived = true, String? language, bool check2fa = false}) => {
        'Content-Type': 'application/json',
        'ClientId': EbbConfig.clientId,
        'endpoint-version': EbbConfig.endpointVersion,
        if (language != null) 'x-language': language,
        'x-long-lived-refresh-token': longLived.toString(),
        if (check2fa) 'x-check-2fa': 'true',
      };

  Tokens _parseTokens(Map<String, dynamic> body, {String language = EbbConfig.defaultLanguage}) {
    final err = body['error'];
    final access = body['accessToken'] as String?;
    final refresh = body['refreshToken'] as String?;
    if (access == null || refresh == null || (err is String && err.isNotEmpty)) {
      throw AuthApiException('Auth rejected: ${err ?? 'missing tokens'}');
    }
    return Tokens(accessToken: access, refreshToken: refresh, language: language);
  }

  /// Native email/password sign-in.
  Future<SignInResult> signInWithPassword({
    required String username,
    required String password,
    bool rememberMe = true,
    String language = EbbConfig.defaultLanguage,
  }) async {
    final res = await _http.post(
      Uri.parse(EbbConfig.signInEndpoint),
      headers: _authHeaders(longLived: rememberMe, language: language),
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw AuthApiException('Sign-in failed', statusCode: res.statusCode);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['accessToken'] != null) {
      return SignInResult.success(_parseTokens(body, language: language));
    }
    return SignInResult.twoFactor(TwoFactorChallenge.fromJson(body));
  }

  /// Ask the backend to send a one-time code via [type] (e.g. "EMAIL"/"SMS").
  Future<void> requestTwoFactor({required String ref, required String type}) async {
    final res = await _http.post(
      Uri.parse(EbbConfig.twoFactorRequestEndpoint),
      headers: _authHeaders(),
      body: jsonEncode({'ref': ref, 'type': type}),
    );
    if (res.statusCode >= 400) {
      throw AuthApiException('2FA request failed', statusCode: res.statusCode);
    }
  }

  /// Confirm the one-time [pin] and receive tokens.
  Future<Tokens> confirmTwoFactor({
    required String ref,
    required String pin,
    bool rememberMe = true,
    String language = EbbConfig.defaultLanguage,
  }) async {
    final res = await _http.post(
      Uri.parse(EbbConfig.twoFactorConfirmEndpoint),
      headers: _authHeaders(longLived: rememberMe, language: language, check2fa: true),
      body: jsonEncode({'ref': ref, 'pin': pin}),
    );
    if (res.statusCode != 200) {
      throw AuthApiException('2FA confirm failed', statusCode: res.statusCode);
    }
    return _parseTokens(jsonDecode(res.body) as Map<String, dynamic>, language: language);
  }

  /// Rotate tokens via /auth/refresh.
  Future<Tokens> refresh(String refreshToken, {String language = EbbConfig.defaultLanguage}) async {
    final res = await _http.post(
      Uri.parse(EbbConfig.refreshEndpoint),
      headers: _authHeaders(language: language),
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (res.statusCode != 200) {
      throw AuthApiException('Refresh failed', statusCode: res.statusCode);
    }
    return _parseTokens(jsonDecode(res.body) as Map<String, dynamic>, language: language);
  }

  void close() => _http.close();
}
