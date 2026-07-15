import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_controller.dart';
import '../config.dart';

class GraphQLException implements Exception {
  GraphQLException(this.operationName, this.messages, {this.statusCode});
  final String operationName;
  final List<String> messages;
  final int? statusCode;

  bool get isAuthError =>
      statusCode == 401 ||
      messages.any((m) {
        final l = m.toLowerCase();
        return l.contains('jwt expired') ||
            l.contains('unauthorized') ||
            l.contains('unauthenticated');
      });

  @override
  String toString() => 'GraphQLException($operationName): ${messages.join('; ')}';
}

/// Abstraction over the network so the web build can swap in a CORS proxy
/// while mobile talks to the backend directly.
abstract class GraphQLTransport {
  /// Returns the `data` map, or throws [GraphQLException] on GraphQL/HTTP error.
  Future<Map<String, dynamic>> execute({
    required String operationName,
    required String query,
    required Map<String, dynamic> variables,
    required String accessToken,
    required String language,
  });
}

/// Direct transport — posts straight to the EBB GraphQL endpoint (mobile).
class DirectGraphQLTransport implements GraphQLTransport {
  DirectGraphQLTransport({http.Client? client, this.endpoint = EbbConfig.graphqlEndpoint})
      : _http = client ?? http.Client();

  final http.Client _http;
  final String endpoint;

  @override
  Future<Map<String, dynamic>> execute({
    required String operationName,
    required String query,
    required Map<String, dynamic> variables,
    required String accessToken,
    required String language,
  }) async {
    final res = await _http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-language': language,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'operationName': operationName,
        'variables': variables,
        'query': query,
      }),
    );

    if (res.statusCode == 401) {
      throw GraphQLException(operationName, const ['Unauthorized'], statusCode: 401);
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw GraphQLException(operationName, ['HTTP ${res.statusCode}: bad body'],
          statusCode: res.statusCode);
    }

    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final msgs = errors.map((e) => (e is Map ? e['message'] : e).toString()).toList();
      throw GraphQLException(operationName, msgs, statusCode: res.statusCode);
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw GraphQLException(operationName, ['No data in response'], statusCode: res.statusCode);
    }
    return data;
  }
}

/// Minimal seam the repositories depend on, so they can be tested with a fake.
abstract class GraphQLExecutor {
  Future<Map<String, dynamic>> query(
    String operationName,
    String query,
    Map<String, dynamic> variables,
  );
}

/// High-level client: injects the access token, and on an auth error refreshes
/// once and retries transparently.
class EbbApi implements GraphQLExecutor {
  EbbApi(this.transport, this.auth);

  final GraphQLTransport transport;
  final AuthController auth;

  @override
  Future<Map<String, dynamic>> query(
    String operationName,
    String query,
    Map<String, dynamic> variables,
  ) async {
    var token = await auth.validAccessToken();
    try {
      return await transport.execute(
        operationName: operationName,
        query: query,
        variables: variables,
        accessToken: token,
        language: auth.language,
      );
    } on GraphQLException catch (e) {
      if (!e.isAuthError) rethrow;
      token = await auth.forceRefresh();
      return transport.execute(
        operationName: operationName,
        query: query,
        variables: variables,
        accessToken: token,
        language: auth.language,
      );
    }
  }
}
