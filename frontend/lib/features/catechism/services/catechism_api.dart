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

  Future<Map<String, dynamic>> teacherClasses(int page) =>
      _client.get('/catechism-teacher/classes', (json) => json,
          query: {'page': page, 'limit': 20});

  Future<Map<String, dynamic>> requestTeacherApproval() =>
      _client.post('/catechism-teacher/classes/requests', (json) => json);

  Future<Map<String, dynamic>> teacherRequests(String churchId) => _client.get(
      '/churches/$churchId/catechism-classes/teacher-requests', (json) => json);

  Future<void> reviewTeacherRequest(String churchId, String requestId,
      {required String status, String? classId}) async {
    await _client.patch(
        '/churches/$churchId/catechism-classes/teacher-requests/$requestId',
        (json) => json,
        body: {'status': status, 'classId': classId});
  }

  Future<Map<String, dynamic>> teacherCandidates(
          String churchId, String? classId) =>
      _client.get(
          '/churches/$churchId/catechism-classes/teachers', (json) => json,
          query: {if (classId != null) 'classId': classId});

  Future<void> assignTeacher(String churchId, String classId, String userId,
      {bool remove = false}) async {
    await _client.post(
        '/churches/$churchId/catechism-classes/teachers', (json) => json,
        body: {'classId': classId, 'userId': userId, 'remove': remove});
  }

  Future<Map<String, dynamic>> workspace(String classId, int page) =>
      _client.get('/catechism-classes/$classId/workspace', (json) => json,
          query: {'page': page, 'limit': 20});

  Future<Map<String, dynamic>> materials(String classId) =>
      _client.get('/catechism-classes/$classId/materials', (json) => json);

  Future<Map<String, dynamic>> uploadNote(
    String classId, {
    required List<int> bytes,
    required String fileName,
    required String title,
    required String description,
  }) =>
      _client.uploadBytesJson('/catechism-classes/$classId/materials',
          bytes: bytes,
          field: 'file',
          fileName: fileName,
          fields: {'title': title, 'description': description});

  Future<Map<String, dynamic>> shareVideo(
          String classId, Map<String, dynamic> body) =>
      _client.post(
          '/catechism-classes/$classId/materials/video', (json) => json,
          body: body);

  Future<void> deleteMaterial(String classId, String materialId) =>
      _client.delete('/catechism-classes/$classId/materials/$materialId');

  Future<int> downloadMaterial(
          String classId, String materialId, String savePath) =>
      _client.download(
          '/catechism-classes/$classId/materials/$materialId/download',
          savePath);

  Future<List<Map<String, dynamic>>> listTests(String classId) => _client.get(
        '/catechism-classes/$classId/tests',
        (json) => (json['tests'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );

  Future<Map<String, dynamic>> createTest(
          String classId, String name, int maximum) =>
      _client.post('/catechism-classes/$classId/tests', (json) => json,
          body: {'name': name, 'maximum': maximum});

  Future<Map<String, dynamic>> testMarks(String classId, String name) =>
      _client.get(
          '/catechism-classes/$classId/tests/${Uri.encodeComponent(name)}',
          (json) => json);

  Future<void> updateTestMark(
      String classId, String name, String enrollmentId, int score) async {
    await _client.put(
        '/catechism-classes/$classId/tests/${Uri.encodeComponent(name)}/students/$enrollmentId',
        (json) => json,
        body: {'score': score});
  }

  Future<Map<String, dynamic>> studentHistory(
    String classId,
    String studentId,
    int page,
  ) =>
      _client.get(
        '/catechism-classes/$classId/workspace/students/$studentId',
        (json) => json,
        query: {'page': page, 'limit': 20},
      );
  Future<void> saveWorkspace(
      String classId, String action, Map<String, dynamic> body) async {
    await _client.post(
        "/catechism-classes/$classId/workspace/$action", (json) => json,
        body: body);
  }

  Future<void> decideAdmission(String enrollmentId, String status) async {
    await _client.patch(
        '/catechism-enrollments/$enrollmentId/status', (json) => json,
        body: {'status': status});
  }

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

  Future<CatechismClass> createClass(
          String churchId, Map<String, dynamic> body) =>
      _client.post(
          '/churches/$churchId/catechism-classes', CatechismClass.fromJson,
          body: body);

  Future<CatechismClass> updateClass(String id, Map<String, dynamic> body) =>
      _client.put('/catechism-classes/$id', CatechismClass.fromJson,
          body: body);

  Future<void> deleteClass(String id) =>
      _client.delete('/catechism-classes/$id');

  Future<PaginatedResponse<CatechismEnrollment>> listClassEnrollments(
    String classId, {
    int page = 1,
    int limit = 50,
    String? search,
  }) =>
      _client.get(
        '/catechism-classes/$classId/enrollments',
        (json) =>
            PaginatedResponse.fromJson(json, CatechismEnrollment.fromJson),
        query: {
          'page': page,
          'limit': limit,
          if (search != null) 'search': search
        },
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
        (json) =>
            PaginatedResponse.fromJson(json, CatechismEnrollment.fromJson),
        query: {
          'page': page,
          'limit': limit,
          if (search != null) 'search': search
        },
      );

  Future<CatechismEnrollment> updateEnrollmentStatus(
          String id, String status) =>
      _client.patch(
        '/catechism-enrollments/$id/status',
        CatechismEnrollment.fromJson,
        body: {'status': status},
      );

  Future<CatechismEnrollment> withdrawEnrollment(String id) => _client.patch(
      '/catechism-enrollments/$id/withdraw', CatechismEnrollment.fromJson);

  Future<PaginatedResponse<CatechismSession>> listSessions(
    String classId, {
    int page = 1,
    int limit = 50,
    String? search,
  }) =>
      _client.get(
        '/catechism-classes/$classId/sessions',
        (json) => PaginatedResponse.fromJson(json, CatechismSession.fromJson),
        query: {
          'page': page,
          'limit': limit,
          if (search != null) 'search': search
        },
      );

  Future<CatechismSession> createSession(
          String classId, Map<String, dynamic> body) =>
      _client.post(
          '/catechism-classes/$classId/sessions', CatechismSession.fromJson,
          body: body);

  Future<CatechismSession> updateSession(
          String id, Map<String, dynamic> body) =>
      _client.put('/catechism-sessions/$id', CatechismSession.fromJson,
          body: body);

  Future<void> deleteSession(String id) =>
      _client.delete('/catechism-sessions/$id');
}
