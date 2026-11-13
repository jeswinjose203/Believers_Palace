import 'dart:convert';
import 'dart:io';
 
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
 
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
    final trimmedBase = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0,apiBaseUrl.length - 1) : apiBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final resolved = Uri.parse('$trimmedBase$normalizedPath');
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
 
  Future<Map<String, dynamic>> getRaw(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.get(
      _uri(path, query),
      headers: _headers(),
    );
    _check(response);
    final body = _decode(response);
    if (body == null) throw ApiException(0, 'Empty response');
    return body;
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
 
  /// Uploads a multipart file and returns the decoded JSON response map. Use
  /// for endpoints whose response is not wrapped in a typed model (e.g. media
  /// uploads returning {url, fileName, mimeType, fileSize}).
  Future<Map<String, dynamic>> uploadMultipartJson(
    String path, {
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
    return decoded;
  }
 
  /// Uploads raw bytes as a multipart file part and returns the decoded JSON
  /// response. Works on every platform (including web) since it does not rely
  /// on a filesystem path.
  Future<Map<String, dynamic>> uploadBytesJson(
    String path, {
    required List<int> bytes,
    required String field,
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path, null))
      ..headers.addAll(_headers(multipart: true))
      ..files.add(http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: fileName.isEmpty ? 'upload' : fileName,
        contentType: _imageMediaType(fileName),
      ));
 
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _check(response);
    final decoded = _decode(response);
    if (decoded == null) throw ApiException(0, 'Empty response');
    return decoded;
  }
 
  /// Infers an image MediaType from a filename extension. Falls back to a
  /// generic binary type; the server also accepts the filename extension.
  MediaType? _imageMediaType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    return null;
  }
}