import 'dart:io';
 
import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../core/api_client.dart';
import '../models/calendar_models.dart';
import '../models/models.dart';
 
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
 
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(apiClientProvider));
});
 
class ApiService {
  final ApiClient _client;
 
  ApiService(this._client);
 
  void setToken(String? token) => _client.setToken(token);
 
  // Auth
  Future<AuthResponse> login(String email, String password) => _client.post(
        '/auth/login',
        AuthResponse.fromJson,
        body: {'email': email, 'password': password},
      );
 
  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? unit,
    String? churchId,
  }) =>
      _client.post(
        '/auth/register',
        AuthResponse.fromJson,
        body: {
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'unit': unit,
          'churchId': churchId,
        },
      );
 
  Future<AuthResponse> refresh(String refreshToken) => _client.post(
        '/auth/refresh',
        AuthResponse.fromJson,
        body: {'refreshToken': refreshToken},
      );
 
  Future<void> logout(String refreshToken) =>
      _client.postVoid('/auth/logout', body: {'refreshToken': refreshToken});
 
  Future<void> logoutAll() => _client.postVoid('/users/logout-all');
 
  Future<void> forgotPassword(String email) =>
      _client.postVoid('/auth/forgot-password', body: {'email': email});
 
  Future<void> resetPassword(String token, String newPassword) =>
      _client.postVoid('/auth/reset-password',
          body: {'token': token, 'newPassword': newPassword});
 
  Future<void> verifyEmail(String token) =>
      _client.postVoid('/auth/verify-email', body: {'token': token});
 
  Future<void> resendVerification(String email) =>
      _client.postVoid('/auth/resend-verification', body: {'email': email});
 
  // Users
  Future<User> getMe() => _client.get('/users/me', User.fromJson);
 
  Future<User> updateMe(Map<String, dynamic> body) =>
      _client.put('/users/me', User.fromJson, body: body);
 
  Future<PaginatedResponse<User>> listUsers({
    String? churchId,
    String? role,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/users',
        (json) => PaginatedResponse.fromJson(json, User.fromJson),
        query: {
          if (churchId != null) 'churchId': churchId,
          if (role != null) 'role': role,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<User> updateRole(String userId, String role) =>
      _client.patch('/users/$userId/role', User.fromJson, body: {'role': role});
 
  Future<UserStats> getUserStats({String? churchId}) => _client.get(
        '/users/stats',
        UserStats.fromJson,
        query: {if (churchId != null) 'churchId': churchId},
      );
 
  // Churches
  Future<PaginatedResponse<Church>> listChurches({
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches',
        (json) => PaginatedResponse.fromJson(json, Church.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<Church> createChurch(Map<String, dynamic> body) =>
      _client.post('/churches', Church.fromJson, body: body);
 
  Future<Church> getChurch(String id) =>
      _client.get('/churches/$id', Church.fromJson);
 
  Future<Church> updateChurch(String id, Map<String, dynamic> body) =>
      _client.put('/churches/$id', Church.fromJson, body: body);
 
  Future<void> deleteChurch(String id) => _client.delete('/churches/$id');
 
  // Announcements
  Future<PaginatedResponse<Announcement>> listAnnouncements(
    String churchId, {
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches/$churchId/announcements',
        (json) => PaginatedResponse.fromJson(json, Announcement.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<Announcement> createAnnouncement(
          String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/announcements',
          Announcement.fromJson,
          body: body);
 
  Future<Announcement> updateAnnouncement(
          String id, Map<String, dynamic> body) =>
      _client.put('/announcements/$id', Announcement.fromJson, body: body);
 
  Future<void> deleteAnnouncement(String id) =>
      _client.delete('/announcements/$id');
 
  // Halls
  Future<PaginatedResponse<Hall>> listHalls(
    String churchId, {
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches/$churchId/halls',
        (json) => PaginatedResponse.fromJson(json, Hall.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<Hall> getHall(String id) => _client.get('/halls/$id', Hall.fromJson);
 
  Future<Hall> createHall(String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/halls', Hall.fromJson, body: body);
 
  Future<Hall> updateHall(String id, Map<String, dynamic> body) =>
      _client.put('/halls/$id', Hall.fromJson, body: body);
 
  Future<void> deleteHall(String id) => _client.delete('/halls/$id');
 
  // Bookings
  Future<PaginatedResponse<Booking>> listChurchBookings(
    String churchId, {
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches/$churchId/bookings',
        (json) => PaginatedResponse.fromJson(json, Booking.fromJson),
        query: {
          if (status != null) 'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<PaginatedResponse<Booking>> listMyBookings({
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/bookings',
        (json) => PaginatedResponse.fromJson(json, Booking.fromJson),
        query: {
          if (status != null) 'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<Booking> createBooking(String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/bookings', Booking.fromJson, body: body);
 
  Future<Booking> getBooking(String id) =>
      _client.get('/bookings/$id', Booking.fromJson);
 
  Future<Booking> updateBookingStatus(
          String id, String status, String? adminNotes) =>
      _client.patch('/bookings/$id/status', Booking.fromJson, body: {
        'status': status,
        'adminNotes': adminNotes,
      });
 
  Future<Booking> cancelBooking(String id, {String? reason}) =>
      _client.patch('/bookings/$id/cancel', Booking.fromJson,
          body: reason == null ? null : {'reason': reason});
 
  // Events
  Future<PaginatedResponse<Event>> listEvents(
    String churchId, {
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches/$churchId/events',
        (json) => PaginatedResponse.fromJson(json, Event.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<Event> createEvent(String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/events', Event.fromJson, body: body);
 
  Future<Event> getEvent(String id) =>
      _client.get('/events/$id', Event.fromJson);
 
  Future<Event> updateEvent(String id, Map<String, dynamic> body) =>
      _client.put('/events/$id', Event.fromJson, body: body);
 
  Future<void> deleteEvent(String id) => _client.delete('/events/$id');
 
  Future<EventRegistration> registerForEvent(
          String eventId, Map<String, dynamic> body) =>
      _client.post('/events/$eventId/register', EventRegistration.fromJson,
          body: body);
 
  Future<void> unregisterFromEvent(String eventId) =>
      _client.delete('/events/$eventId/register');
 
  Future<PaginatedResponse<EventRegistration>> listEventRegistrations(
    String eventId, {
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/events/$eventId/registrations',
        (json) => PaginatedResponse.fromJson(json, EventRegistration.fromJson),
        query: {'page': page, 'limit': limit},
      );
 
  // Event chat messages
  Future<PaginatedResponse<ChatMessage>> listEventMessages(
    String eventId, {
    int page = 1,
    int limit = 100,
  }) =>
      _client.get(
        '/events/$eventId/messages',
        (json) => PaginatedResponse.fromJson(json, ChatMessage.fromJson),
        query: {'page': page, 'limit': limit},
      );
 
  /// Cursor-based chat listing. With neither [before] nor [after], returns the
  /// latest [limit] messages. [before]/[after] are message `seq` values.
  Future<ChatCursorPage> listEventMessagesCursor(
    String eventId, {
    int? before,
    int? after,
    int limit = 50,
  }) =>
      _client.get(
        '/events/$eventId/messages',
        ChatCursorPage.fromJson,
        query: {
          if (before != null) 'before': before,
          if (after != null) 'after': after,
          if (before == null && after == null) 'latest': 1,
          'limit': limit,
        },
      );
 
  Future<ChatMessage> postEventMessage(String eventId, String content) =>
      _client.post(
        '/events/$eventId/messages',
        ChatMessage.fromJson,
        body: {'content': content},
      );
 
  Future<void> deleteEventMessage(String eventId, String messageId) =>
      _client.delete('/events/$eventId/messages/$messageId');
 
  // Cemetery plots
  Future<PaginatedResponse<CemeteryPlot>> listCemeteryPlots(
    String churchId, {
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches/$churchId/cemetery-plots',
        (json) => PaginatedResponse.fromJson(json, CemeteryPlot.fromJson),
        query: {
          if (status != null) 'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<CemeteryPlot> createCemeteryPlot(
          String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/cemetery-plots', CemeteryPlot.fromJson,
          body: body);
 
  Future<CemeteryPlot> updateCemeteryPlot(
          String id, Map<String, dynamic> body) =>
      _client.put('/cemetery-plots/$id', CemeteryPlot.fromJson, body: body);
 
  Future<void> deleteCemeteryPlot(String id) =>
      _client.delete('/cemetery-plots/$id');
 
  // Cemetery service requests
  Future<PaginatedResponse<CemeteryServiceRequest>> listCemeteryRequests(
    String churchId, {
    String? status,
    String? type,
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/churches/$churchId/cemetery-service-requests',
        (json) => PaginatedResponse.fromJson(json, CemeteryServiceRequest.fromJson),
        query: {
          if (status != null) 'status': status,
          if (type != null) 'type': type,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<CemeteryServiceRequest> createCemeteryRequest(
          String churchId, Map<String, dynamic> body) =>
      _client.post('/churches/$churchId/cemetery-service-requests',
          CemeteryServiceRequest.fromJson,
          body: body);
 
  Future<CemeteryServiceRequest> getCemeteryRequest(String id) =>
      _client.get('/cemetery-service-requests/$id', CemeteryServiceRequest.fromJson);
 
  Future<CemeteryServiceRequest> updateCemeteryRequestStatus(
          String id, Map<String, dynamic> body) =>
      _client.patch('/cemetery-service-requests/$id/status',
          CemeteryServiceRequest.fromJson,
          body: body);
 
  // Certificates
  Future<PaginatedResponse<Certificate>> listCertificates(
    String userId, {
    String? type,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/users/$userId/certificates',
        (json) => PaginatedResponse.fromJson(json, Certificate.fromJson),
        query: {
          if (type != null) 'type': type,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<Certificate> uploadCertificate(
    String userId, {
    required File file,
    required String type,
    required String certificateNumber,
    required String fullName,
    String? issueDate,
    String? notes,
  }) =>
      _client.uploadMultipart(
        '/users/$userId/certificates',
        Certificate.fromJson,
        file: file,
        field: 'file',
        fields: {
          'type': type,
          'certificateNumber': certificateNumber,
          'fullName': fullName,
          if (issueDate != null) 'issueDate': issueDate,
          if (notes != null) 'notes': notes,
        },
      );
 
  Future<int> downloadCertificate(String certificateId, String savePath) =>
      _client.download('/certificates/$certificateId/download', savePath);
 
  // Media (image upload). Returns the public URL of the stored image, which can
  // be saved into fields like church logo, profile picture, or event image.
  Future<String> uploadImage(File file) async {
    final res = await _client.uploadMultipartJson(
      '/media/upload',
      file: file,
      field: 'file',
      fields: const {},
    );
    return res['url'] as String;
  }
 
  /// Uploads image bytes (works on all platforms, including web where a file
  /// path is unavailable). [fileName] is used to infer the content type.
  Future<String> uploadImageBytes(List<int> bytes, String fileName) async {
    final res = await _client.uploadBytesJson(
      '/media/upload',
      bytes: bytes,
      field: 'file',
      fileName: fileName,
    );
    return res['url'] as String;
  }
 
  // Personal calendar
  Future<CalendarPreferences> getCalendarPreferences() =>
      _client.get('/users/me/calendar/preferences', CalendarPreferences.fromJson);
 
  Future<CalendarPreferences> patchCalendarPreferences(Map<String, dynamic> body) =>
      _client.patch(
        '/users/me/calendar/preferences',
        CalendarPreferences.fromJson,
        body: body,
      );
 
  Future<PaginatedResponse<PersonalCalendarEvent>> listCalendarEvents({
    String? search,
    String? category,
    int page = 1,
    int limit = 50,
  }) =>
      _client.get(
        '/users/me/calendar/events',
        (json) => PaginatedResponse.fromJson(json, PersonalCalendarEvent.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (category != null && category.isNotEmpty) 'category': category,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<PersonalCalendarEvent> createCalendarEvent(Map<String, dynamic> body) =>
      _client.post('/users/me/calendar/events', PersonalCalendarEvent.fromJson, body: body);
 
  Future<PersonalCalendarEvent> updateCalendarEvent(String id, Map<String, dynamic> body) =>
      _client.patch('/users/me/calendar/events/$id', PersonalCalendarEvent.fromJson, body: body);
 
  Future<void> deleteCalendarEvent(String id) =>
      _client.delete('/users/me/calendar/events/$id');
 
  Future<List<ScheduleItem>> getCalendarSchedule(DateTime from, DateTime to) async {
    final json = await _client.getRaw(
      '/users/me/calendar/schedule',
      query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String()},
    );
    return (json['data'] as List<dynamic>)
        .map((e) => ScheduleItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
 
  Future<PaginatedResponse<CalendarTask>> listCalendarTasks({int page = 1, int limit = 50}) =>
      _client.get(
        '/users/me/calendar/tasks',
        (json) => PaginatedResponse.fromJson(json, CalendarTask.fromJson),
        query: {'page': page, 'limit': limit},
      );
 
  Future<CalendarTask> createCalendarTask(Map<String, dynamic> body) =>
      _client.post('/users/me/calendar/tasks', CalendarTask.fromJson, body: body);
 
  Future<CalendarTask> patchCalendarTask(String id, Map<String, dynamic> body) =>
      _client.patch('/users/me/calendar/tasks/$id', CalendarTask.fromJson, body: body);
 
  Future<void> deleteCalendarTask(String id) => _client.delete('/users/me/calendar/tasks/$id');
 
  Future<PaginatedResponse<CalendarGoal>> listCalendarGoals({
    String? status,
    int page = 1,
    int limit = 50,
  }) =>
      _client.get(
        '/users/me/calendar/goals',
        (json) => PaginatedResponse.fromJson(json, CalendarGoal.fromJson),
        query: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<CalendarGoal> createCalendarGoal(Map<String, dynamic> body) =>
      _client.post('/users/me/calendar/goals', CalendarGoal.fromJson, body: body);
 
  Future<CheckInResponse> checkInGoal(String goalId, String dateYmd, {String? note}) =>
      _client.put(
        '/users/me/calendar/goals/$goalId/checkins/$dateYmd',
        CheckInResponse.fromJson,
        body: note != null ? {'note': note} : <String, dynamic>{},
      );
 
  Future<List<CalendarAchievement>> listCalendarAchievements() async {
    final json = await _client.getRaw('/users/me/calendar/achievements');
    return (json['data'] as List<dynamic>)
        .map((e) => CalendarAchievement.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}