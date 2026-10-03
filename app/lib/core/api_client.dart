import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin JSON client for the NestJS API (`/api` prefix, Bearer JWT).
class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.token,
    this.onUnauthorized,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// Server root, e.g. `http://192.168.1.50:3000` (no `/api`).
  final String baseUrl;
  final String? token;

  /// Called on 401 for authenticated requests (expired or revoked session).
  final void Function()? onUnauthorized;

  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl/api$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(_timeout));
    } on TimeoutException {
      throw ApiException(0, 'El servidor no respondió a tiempo. Intenta de nuevo.');
    } catch (_) {
      throw ApiException(0, translateServerMessage(0, null));
    }

    final decoded = response.bodyBytes.isEmpty ? null : _tryDecode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final error = ApiException.fromResponse(response.statusCode, decoded);
    if (error.isUnauthorized && token != null) onUnauthorized?.call();
    throw error;
  }

  static Object? _tryDecode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)); // explicit UTF-8: "Ají de gallina"
    } catch (_) {
      return null;
    }
  }
}
