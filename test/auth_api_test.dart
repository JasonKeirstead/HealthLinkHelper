import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthlink_scanner/src/auth/auth_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('password sign-in returns tokens and sends required headers', () async {
    late http.Request captured;
    final api = AuthApi(client: MockClient((req) async {
      captured = req;
      return _json({'type': 'Bearer', 'accessToken': 'a.b.c', 'refreshToken': 'r.e.f', 'error': ''});
    }));

    final result = await api.signInWithPassword(username: 'me@x.com', password: 'pw');

    expect(result.needsTwoFactor, isFalse);
    expect(result.tokens!.accessToken, 'a.b.c');
    expect(captured.url.path, '/auth/sign-in');
    expect(captured.headers['ClientId'], 'd0Vi');
    expect(captured.headers['endpoint-version'], '2024-02-07');
    expect(jsonDecode(captured.body)['username'], 'me@x.com');
  });

  test('password sign-in surfaces a 2FA challenge when no token is returned', () async {
    final api = AuthApi(client: MockClient((req) async {
      return _json({
        'ref': 'REF123',
        'primaryTwoFactorAuthenticationMethod': 'EMAIL',
        'isEmailEnabled': true,
        'isSMSEnabled': false,
        'email': 'm***@x.com',
      });
    }));

    final result = await api.signInWithPassword(username: 'me@x.com', password: 'pw');

    expect(result.needsTwoFactor, isTrue);
    expect(result.challenge!.ref, 'REF123');
    expect(result.challenge!.primaryMethod, 'EMAIL');
    expect(result.challenge!.emailEnabled, isTrue);
  });

  test('2FA confirm returns tokens and sets x-check-2fa', () async {
    late http.Request captured;
    final api = AuthApi(client: MockClient((req) async {
      captured = req;
      return _json({'type': 'Bearer', 'accessToken': 'a', 'refreshToken': 'r', 'error': ''});
    }));

    final tokens = await api.confirmTwoFactor(ref: 'REF123', pin: '123456');

    expect(tokens.refreshToken, 'r');
    expect(captured.headers['x-check-2fa'], 'true');
    expect(jsonDecode(captured.body), {'ref': 'REF123', 'pin': '123456'});
  });

  test('refresh posts refreshToken with ClientId', () async {
    late http.Request captured;
    final api = AuthApi(client: MockClient((req) async {
      captured = req;
      return _json({'type': 'Bearer', 'accessToken': 'a2', 'refreshToken': 'r2', 'error': ''});
    }));

    final tokens = await api.refresh('old-refresh');

    expect(tokens.accessToken, 'a2');
    expect(captured.url.path, '/auth/refresh');
    expect(captured.headers['ClientId'], 'd0Vi');
    expect(jsonDecode(captured.body), {'refreshToken': 'old-refresh'});
  });

  test('non-200 sign-in throws', () async {
    final api = AuthApi(client: MockClient((req) async => _json({'error': 'bad'}, 401)));
    expect(
      () => api.signInWithPassword(username: 'x', password: 'y'),
      throwsA(isA<AuthApiException>()),
    );
  });
}
