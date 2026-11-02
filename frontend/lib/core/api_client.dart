import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException(this.statusCode, this.message, {this.code});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  final http.Client _client;
  String? _token;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  void setToken(String? token) => _token = token;

  Map<String, String> _headers({bool multipart = false}) {
    final headers = <String, String>{};
    if (!multipart) headers['Content-Type'] = 'application/json';
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Uri _uri(String path, Map<String, dynamic>? query) {
    final base = Uri.parse(apiBaseUrl);
    final resolved = base.resolve(path.startsWith('/') ? path.substring(1) : path);
    if (query == null || query.isEmpty) return resolved;
    return resolved.replace(
      queryParameters: {
        for (final e in query.entries)
          if (e.value != null) e.key: e.value.toString(),
      },
    );
  }

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final body = _decode(response);
    final error = body != null ? ErrorResponse.fromJson(body) : null;
    throw ApiException(
      response.statusCode,
      error?.message ?? 'Request failed',
      code: error?.code,
    );
  }

  Map<String, dynamic>? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<T> get<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.get(
      _uri(path, query),
      headers: _headers(),
    );
    _check(response);
    final body = _decode(response);
    if (body == null) throw ApiException(0, 'Empty response');
    return fromJson(body);
  }

  Future<T> post<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client.post(
      _uri(path, null),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    _check(response);
    final decoded = _decode(response);
    if (decoded == null) throw ApiException(0, 'Empty response');
    return fromJson(decoded);
  }

  Future<T> put<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client.put(
      _uri(path, null),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    _check(response);
    final decoded = _decode(response);
    if (decoded == null) throw ApiException(0, 'Empty response');
    return fromJson(decoded);
  }

  Future<void> delete(String path) async {
    final response = await _client.delete(
      _uri(path, null),
      headers: _headers(),
    );
    _check(response);
  }

  /// POSTs a JSON body and ignores any response payload. Use for endpoints
  /// that return 204 No Content or a message envelope.
  Future<void> postVoid(String path, {Map<String, dynamic>? body}) async {
    final response = await _client.post(
      _uri(path, null),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    _check(response);
  }

  Future<T> patch<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _client.patch(
      _uri(path, null),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    _check(response);
    final decoded = _decode(response);
    if (decoded == null) throw ApiException(0, 'Empty response');
    return fromJson(decoded);
  }

  Future<int> download(String path, String savePath) async {
    final request = http.Request('GET', _uri(path, null));
    request.headers.addAll(_headers());
    final streamed = await _client.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(streamed.statusCode, 'Download failed');
    }
    final file = File(savePath);
    await streamed.stream.pipe(file.openWrite());
    return file.lengthSync();
  }

  Future<T> uploadMultipart<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    required File file,
    required String field,
    required Map<String, String> fields,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path, null))
      ..headers.addAll(_headers(multipart: true))
      ..files.add(await http.MultipartFile.fromPath(field, file.path))
      ..fields.addAll(fields);

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _check(response);
    final decoded = _decode(response);
    if (decoded == null) throw ApiException(0, 'Empty response');
    return fromJson(decoded);
  }
}
