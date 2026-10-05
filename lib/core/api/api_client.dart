import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

typedef Json = Map<String, Object?>;

/// Which access token a call carries. Customer and staff tokens are never interchangeable.
enum AuthKind { none, customer, staff }

/// Reads the current token of a kind, or null when signed out.
typedef TokenReader = String? Function(AuthKind kind);

/// Called when an authenticated call gets `401 UNAUTHENTICATED`: the token is dead.
typedef UnauthenticatedHandler = void Function(AuthKind kind);

/// The HTTP transport for `/api/v1`: JSON in and out, bearer tokens, and one error type.
///
/// Every non-2xx answer becomes an [ApiException] carrying the server's code and message;
/// a request that never got an answer becomes [ApiException.network].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokenFor,
    this.onUnauthenticated,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 20),
  }) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       _clientFactory = clientFactory ?? http.Client.new {
    _client = _clientFactory();
  }

  final String baseUrl;
  final TokenReader tokenFor;
  final UnauthenticatedHandler? onUnauthenticated;
  final Duration timeout;
  final http.Client Function() _clientFactory;
  late final http.Client _client;

  Uri uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> headers(AuthKind auth, {String accept = 'application/json'}) {
    final token = auth == AuthKind.none ? null : tokenFor(auth);
    return {'Accept': accept, if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<Json> get(String path, {AuthKind auth = AuthKind.none}) async {
    final body = await _send('GET', path, auth: auth);
    return body ?? const {};
  }

  /// POSTs [body] as JSON. Returns null for `204 No Content`.
  Future<Json?> post(String path, {Object? body, AuthKind auth = AuthKind.none}) =>
      _send('POST', path, auth: auth, body: body);

  /// Opens a long-lived streamed GET (Server-Sent Events) on its own connection.
  ///
  /// The returned [http.Client] must be closed by the caller to end the stream; closing it is
  /// the only way to abort an `http` request. Error statuses are thrown as [ApiException] before
  /// any of the stream is read.
  Future<(http.Client, http.StreamedResponse)> openStream(String path, AuthKind auth) async {
    final client = _clientFactory();
    try {
      final request = http.Request('GET', uri(path))
        ..headers.addAll(headers(auth, accept: 'text/event-stream'))
        ..headers['Cache-Control'] = 'no-cache';
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode != 200) {
        final text = await response.stream.bytesToString();
        throw _failure(response.statusCode, text, auth);
      }
      return (client, response);
    } on ApiException {
      client.close();
      rethrow;
    } on TimeoutException {
      client.close();
      throw const ApiException.network('timeout');
    } on http.ClientException catch (e) {
      client.close();
      throw ApiException.network(e.message);
    }
  }

  Future<Json?> _send(String method, String path, {required AuthKind auth, Object? body}) async {
    final request = http.Request(method, uri(path))..headers.addAll(headers(auth));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiException.network('timeout');
    } on http.ClientException catch (e) {
      throw ApiException.network(e.message);
    }
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.statusCode == 204 || text.isEmpty) return null;
      final decoded = _decode(text);
      if (decoded is Json) return decoded;
      throw ApiException(
        status: response.statusCode,
        code: ApiErrorCode.unexpected,
        message: 'The server sent something unexpected. Please try again.',
      );
    }
    throw _failure(response.statusCode, text, auth);
  }

  ApiException _failure(int status, String text, AuthKind auth) {
    final error = ApiException.fromResponse(status, _decode(text));
    if (error.isUnauthenticated && auth != AuthKind.none) onUnauthenticated?.call(auth);
    return error;
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  void close() => _client.close();
}
