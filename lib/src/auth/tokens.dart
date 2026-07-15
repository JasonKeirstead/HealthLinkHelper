import 'dart:convert';

/// An access/refresh token pair plus the client metadata `/auth/refresh` needs.
///
/// `clientId` / `language` are captured from TELUS's own refresh call during the
/// WebView login and replayed on native refreshes.
class Tokens {
  Tokens({
    required this.accessToken,
    required this.refreshToken,
    this.clientId,
    this.language = 'en',
  }) : expiresAt = decodeJwtExpiry(accessToken);

  final String accessToken;
  final String refreshToken;
  final String? clientId;
  final String language;

  /// From the access-token JWT `exp` claim (UTC). Null if undecodable.
  final DateTime? expiresAt;

  bool isExpired({Duration skew = Duration.zero}) {
    final exp = expiresAt;
    if (exp == null) return true; // unknown → treat as needing refresh
    return DateTime.now().toUtc().add(skew).isAfter(exp);
  }

  Tokens copyWith({String? accessToken, String? refreshToken, String? clientId, String? language}) =>
      Tokens(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        clientId: clientId ?? this.clientId,
        language: language ?? this.language,
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'clientId': clientId,
        'language': language,
      };

  factory Tokens.fromJson(Map<String, dynamic> j) => Tokens(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        clientId: j['clientId'] as String?,
        language: (j['language'] as String?) ?? 'en',
      );
}

/// Decode a JWT's `exp` claim to a UTC [DateTime]. Returns null on any failure.
DateTime? decodeJwtExpiry(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) & ~3, '=');
    final map = jsonDecode(utf8.decode(base64.decode(payload))) as Map<String, dynamic>;
    final exp = map['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}
