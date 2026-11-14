import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../models/models.dart';
import '../../../services/api_service.dart';
import '../models/catechism_models.dart';

final catechismApiProvider = Provider<CatechismApi>((ref) {
  return CatechismApi(ref.watch(apiClientProvider));
});

class CatechismApi {
  final ApiClient _client;

  CatechismApi(this._client);

  Future<PaginatedResponse<CatechismClass>> listClasses(
    String churchId, {
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? level,
  }) =>
      _client.get(
        '/churches/$churchId/catechism-classes',
        (json) => PaginatedResponse.fromJson(json, CatechismClass.fromJson),
        query: {
          'page': page,
          'limit': limit,
          if (search != null && search.isNotEmpty) 'search': search,
          if (status != null && status.isNotEmpty) 'status': status,
          if (level != null && level.isNotEmpty) 'level': level,
        },
      );

  Future<CatechismClass> getClass(String id) =>
      _client.get('/catechism-classes/$id', CatechismClass.fromJson);

  Future<CatechismClass> createClass(String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/catechism-classes', CatechismClass.fromJson, body: body);

  Future<CatechismClass> updateClass(String id, Map<String, dynamic> body) =>
      _client.put('/catechism-classes/$id', CatechismClass.fromJson, body: body);

  Future<void> deleteClass(String id) => _client.delete('/catechism-classes/$id');

  Future<PaginatedResponse<CatechismEnrollment>> listClassEnrollments(
    String classId, {
    int page = 1,
    int limit = 50,
    String? search,
  }) =>
      _client.get(
        '/catechism-classes/$classId/enrollments',
        (json) => PaginatedResponse.fromJson(json, CatechismEnrollment.fromJson),
        query: {'page': page, 'limit': limit, if (search != null) 'search': search},
      );

  Future<CatechismEnrollment> createEnrollment(
    String classId,
    Map<String, dynamic> body,
  ) =>
      _client.post(
        '/catechism-classes/$classId/enrollments',
        CatechismEnrollment.fromJson,
        body: body,
      );

  Future<PaginatedResponse<CatechismEnrollment>> listMyEnrollments({
    int page = 1,
    int limit = 50,
    String? search,
  }) =>
      _client.get(
        '/catechism-enrollments',
        (json) => PaginatedResponse.fromJson(json, CatechismEnrollment.fromJson),
        query: {'page': page, 'limit': limit, if (search != null) 'search': search},
      );

  Future<CatechismEnrollment> updateEnrollmentStatus(String id, String status) =>
      _client.patch(
        '/catechism-enrollments/$id/status',
        CatechismEnrollment.fromJson,
        body: {'status': status},
      );

  Future<CatechismEnrollment> withdrawEnrollment(String id) =>
      _client.patch('/catechism-enrollments/$id/withdraw', CatechismEnrollment.fromJson);

  Future<PaginatedResponse<CatechismSession>> listSessions(
    String classId, {
    int page = 1,
    int limit = 50,
    String? search,
  }) =>
      _client.get(
        '/catechism-classes/$classId/sessions',
        (json) => PaginatedResponse.fromJson(json, CatechismSession.fromJson),
        query: {'page': page, 'limit': limit, if (search != null) 'search': search},
      );

  Future<CatechismSession> createSession(String classId, Map<String, dynamic> body) =>
      _client.post('/catechism-classes/$classId/sessions', CatechismSession.fromJson, body: body);

  Future<CatechismSession> updateSession(String id, Map<String, dynamic> body) =>
      _client.put('/catechism-sessions/$id', CatechismSession.fromJson, body: body);

  Future<void> deleteSession(String id) => _client.delete('/catechism-sessions/$id');
}