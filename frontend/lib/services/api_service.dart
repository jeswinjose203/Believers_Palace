import 'dart:io';
 
import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../core/api_client.dart';
import '../models/calendar_models.dart';
import '../models/community_models.dart';
import '../models/marketplace_models.dart';
import '../models/models.dart';
 
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
 
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(apiClientProvider));
});
 
class ApiService {
  final ApiClient _client;
 
  ApiService(this._client);

  Future<void> verifyAccountPhone(String phone, String token) =>
      _client.postVoid('/users/me/verify-phone', body: {
        'phone': phone,
        'firebaseIdToken': token,
      });
 
  void setToken(String? token, {bool rotated = false}) =>
      _client.setToken(token, rotated: rotated);
  String? get accessToken => _client.accessToken;
  set refreshSession(Future<bool> Function(String)? callback) =>
      _client.refreshSession = callback;

  Future<String> createChatLiveTicket() => _client.post(
        '/chat/live-ticket',
        (json) => json['ticket'] as String,
        body: const <String, dynamic>{},
      );

  Future<Map<String, bool>> listChatPreferences() => _client.get(
        '/chat/preferences',
        (json) => {
          for (final row in json['data'] as List)
            '${row['kind']}.${row['id']}': row['muted'] as bool,
        },
      );

  Future<Map<String, String>> listJoinedCommunityChats() => _client.get(
        '/chat/joined-communities',
        (json) => Map<String, String>.from(json['data'] as Map),
      );

  Future<void> setChatPreference(String kind, String id,
      {bool? muted, bool onlyIfMissing = false}) async {
    await _client.put(
      '/chat/preferences/$kind/$id',
      (_) => true,
      body: {
        if (muted != null) 'muted': muted,
        if (muted == null || onlyIfMissing) 'followOnly': true,
      },
    );
  }

  Future<void> registerChatPushDevice(String token) =>
      _client.postVoid('/chat/push-devices', body: {'token': token});

  Future<void> removeChatPushDevice(String token) =>
      _client.postVoid('/chat/push-devices/remove', body: {'token': token});
 
  // Auth
  Future<AuthResponse> login(String email, String password, {bool teacher = false}) => _client.post(
        teacher ? '/auth/teacher-login' : '/auth/login',
        AuthResponse.fromJson,
        body: {'email': email, 'password': password},
      );
 
  Future<AuthResponse> register({
    required String name,
    required String username,
    required String email,
    required String password,
    required String phone,
    required String firebaseIdToken,
    String? unit,
    String? churchId,
  }) =>
      _client.post(
        '/auth/register',
        AuthResponse.fromJson,
        body: {
          'name': name,
          'username': username,
          'email': email,
          'password': password,
          'phone': phone,
          'firebaseIdToken': firebaseIdToken,
          'unit': unit,
          'churchId': churchId,
        },
      ).timeout(const Duration(seconds: 35));
 
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
  /// latest [limit] messages. An explicit [after] of zero starts from the
  /// beginning of a conversation.
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
 
  Future<ChatMessage> postEventMessage(String eventId, String content, {String? clientId}) =>
      _client.post(
        '/events/$eventId/messages',
        ChatMessage.fromJson,
        body: {'content': content, if (clientId != null) 'clientId': clientId},
      );
 
  Future<void> deleteEventMessage(String eventId, String messageId) =>
      _client.delete('/events/$eventId/messages/$messageId');

  // Communities
  Future<CommunityPage> listCommunityPage({
    required bool joined,
    String? cursor,
  }) async {
    final json = await _client.getRaw('/communities', query: {
      'limit': 30,
      'joined': joined,
      if (cursor != null) 'cursor': cursor,
    });
    return (
      items: (json['data'] as List)
          .map((item) => Community.fromJson(item as Map<String, dynamic>))
          .where((item) => !joined || item.status == 'active' || item.isAdmin)
          .toList(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  Future<Community> createCommunity(
    String name,
    String description, {
    String? image,
  }) =>
      _client.post('/communities', Community.fromJson,
          body: {
            'name': name,
            'description': description,
            if (image != null && image.isNotEmpty) 'image': image,
          });

  Future<Community> updateCommunity(
    String id,
    String name,
    String description, {
    String? image,
  }) =>
      _client.put('/communities/$id', Community.fromJson, body: {
        'name': name,
        'description': description,
        'image': image,
      });

  Future<CommunityMembership> requestCommunityMembership(String id) =>
      _client.post('/communities/$id/requests', CommunityMembership.fromJson);

  Future<List<CommunityMembership>> listCommunityRequests(String id) async {
    final json = await _client.getRaw('/communities/$id/requests');
    return (json['data'] as List)
        .map((item) =>
            CommunityMembership.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<CommunityMembership>> listCommunityMembers(String id) async {
    final json = await _client.getRaw('/communities/$id/members');
    return (json['data'] as List)
        .map((item) =>
            CommunityMembership.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> reviewCommunityRequest(
          String communityId, String requestId, bool approve) =>
      _client.postVoid(
          '/communities/$communityId/requests/$requestId/${approve ? 'approve' : 'decline'}');

  Future<void> removeCommunityMember(String communityId, String userId) =>
      _client.delete('/communities/$communityId/members/$userId');

  Future<void> leaveCommunity(String communityId) =>
      _client.delete('/communities/$communityId/leave');

  Future<CommunityCursorPage> listCommunityMessages(
    String id, {
    int? before,
    int? after,
    int limit = 50,
  }) =>
      _client.get(
        '/communities/$id/messages',
        CommunityCursorPage.fromJson,
        query: {
          if (before != null) 'before': before,
          if (after != null) 'after': after,
          'limit': limit,
        },
      );

  Future<CommunityMessage> postCommunityMessage(String id, String content, {String? clientId}) =>
      _client.post('/communities/$id/messages', CommunityMessage.fromJson,
          body: {'content': content, if (clientId != null) 'clientId': clientId});

  Future<void> deleteCommunityMessage(String id, String messageId) =>
      _client.delete('/communities/$id/messages/$messageId');
 
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
    String? fromDate,
    String? toDate,
    int? upcomingDays,
    String order = 'desc',
    int page = 1,
    int limit = 50,
  }) =>
      _client.get(
        '/users/me/calendar/events',
        (json) => PaginatedResponse.fromJson(json, PersonalCalendarEvent.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (category != null && category.isNotEmpty) 'category': category,
          if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
          if (toDate != null && toDate.isNotEmpty) 'toDate': toDate,
          if (upcomingDays != null) 'upcomingDays': upcomingDays,
          'order': order,
          'page': page,
          'limit': limit,
        },
      );
 
  Future<PersonalCalendarEvent> createCalendarEvent(Map<String, dynamic> body) =>
      _client.post('/users/me/calendar/events', PersonalCalendarEvent.fromJson, body: body);

  Future<PersonalCalendarEvent> getCalendarEvent(String id) =>
      _client.get('/users/me/calendar/events/$id', PersonalCalendarEvent.fromJson);

  Future<PersonalCalendarEvent> updateCalendarEvent(String id, Map<String, dynamic> body) =>
      _client.patch('/users/me/calendar/events/$id', PersonalCalendarEvent.fromJson, body: body);
 
  Future<void> deleteCalendarEvent(String id) =>
      _client.delete('/users/me/calendar/events/$id');
 
  Future<List<ScheduleItem>> getCalendarSchedule(DateTime from, DateTime toExclusive) async {
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = toExclusive.subtract(const Duration(days: 1));
    final json = await _client.getRaw(
      '/users/me/calendar/schedule',
      query: {'fromDate': ymd(fromDay), 'toDate': ymd(toDay.isBefore(fromDay) ? fromDay : toDay)},
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
 
  Future<CalendarGoal> updateCalendarGoal(String id, Map<String, dynamic> body) =>
      _client.patch('/users/me/calendar/goals/$id', CalendarGoal.fromJson, body: body);
 
  Future<void> deleteCalendarGoal(String id) =>
      _client.delete('/users/me/calendar/goals/$id');
 
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

  // Marketplace — categories
  Future<List<MarketplaceCategory>> listMarketplaceCategories(
    String scope, {
    bool all = false,
  }) async {
    final json = await _client.getRaw(
      '/marketplace/categories',
      query: {'scope': scope, if (all) 'all': 'true'},
    );
    return (json['data'] as List)
        .map((e) => MarketplaceCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MarketplaceCategory> createMarketplaceCategory(
    String scope, {
    required String name,
    int sortOrder = 0,
    bool active = true,
  }) =>
      _client.post(
        '/marketplace/categories?scope=$scope',
        MarketplaceCategory.fromJson,
        body: {'name': name, 'sortOrder': sortOrder, 'active': active},
      );

  Future<MarketplaceCategory> updateMarketplaceCategory(
    String id, {
    required String name,
    int? sortOrder,
    bool? active,
  }) =>
      _client.put(
        '/marketplace/categories/$id',
        MarketplaceCategory.fromJson,
        body: {
          'name': name,
          if (sortOrder != null) 'sortOrder': sortOrder,
          if (active != null) 'active': active,
        },
      );

  Future<void> deleteMarketplaceCategory(String id) =>
      _client.delete('/marketplace/categories/$id');

  // Community advertisements
  Future<PaginatedResponse<CommunityAd>> browseCommunityAds({
    String? search,
    String? categoryId,
    int? minPrice,
    int? maxPrice,
    bool excludeSold = false,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/marketplace/community-ads',
        (json) => PaginatedResponse.fromJson(json, CommunityAd.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
          if (minPrice != null) 'minPrice': minPrice,
          if (maxPrice != null) 'maxPrice': maxPrice,
          if (excludeSold) 'excludeSold': 'true',
          'page': page,
          'limit': limit,
        },
      );

  Future<PaginatedResponse<CommunityAd>> listMyCommunityAds({
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/marketplace/community-ads/mine',
        (json) => PaginatedResponse.fromJson(json, CommunityAd.fromJson),
        query: {'page': page, 'limit': limit},
      );

  Future<PaginatedResponse<CommunityAd>> listCommunityAdsAdmin({
    String status = 'pending_approval',
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/marketplace/community-ads/admin',
        (json) => PaginatedResponse.fromJson(json, CommunityAd.fromJson),
        query: {
          'status': status,
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );

  Future<CommunityAd> getCommunityAd(String id) =>
      _client.get('/marketplace/community-ads/$id', CommunityAd.fromJson);

  Future<CommunityAd> createCommunityAd(Map<String, dynamic> body) =>
      _client.post('/marketplace/community-ads', CommunityAd.fromJson, body: body);

  Future<CommunityAd> updateCommunityAd(String id, Map<String, dynamic> body) =>
      _client.put('/marketplace/community-ads/$id', CommunityAd.fromJson, body: body);

  Future<void> deleteCommunityAd(String id) =>
      _client.delete('/marketplace/community-ads/$id');

  Future<CommunityAd> approveCommunityAd(String id) =>
      _client.post('/marketplace/community-ads/$id/approve', CommunityAd.fromJson);

  Future<CommunityAd> rejectCommunityAd(String id, {String? reason}) =>
      _client.post(
        '/marketplace/community-ads/$id/reject',
        CommunityAd.fromJson,
        body: reason != null ? {'reason': reason} : null,
      );

  Future<CommunityAd> markCommunityAdSold(String id) =>
      _client.post('/marketplace/community-ads/$id/sold', CommunityAd.fromJson);

  // Shop products
  Future<PaginatedResponse<ShopProduct>> browseShopProducts({
    String? search,
    String? categoryId,
    int? minPrice,
    int? maxPrice,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/marketplace/shop/products',
        (json) => PaginatedResponse.fromJson(json, ShopProduct.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
          if (minPrice != null) 'minPrice': minPrice,
          if (maxPrice != null) 'maxPrice': maxPrice,
          'page': page,
          'limit': limit,
        },
      );

  Future<PaginatedResponse<ShopProduct>> listShopProductsAdmin({
    String? search,
    int page = 1,
    int limit = 20,
  }) =>
      _client.get(
        '/marketplace/shop/products/admin',
        (json) => PaginatedResponse.fromJson(json, ShopProduct.fromJson),
        query: {
          if (search != null && search.isNotEmpty) 'search': search,
          'page': page,
          'limit': limit,
        },
      );

  Future<ShopProduct> getShopProduct(String id) =>
      _client.get('/marketplace/shop/products/$id', ShopProduct.fromJson);

  Future<ShopProduct> createShopProduct(Map<String, dynamic> body) =>
      _client.post('/marketplace/shop/products', ShopProduct.fromJson, body: body);

  Future<ShopProduct> updateShopProduct(String id, Map<String, dynamic> body) =>
      _client.put('/marketplace/shop/products/$id', ShopProduct.fromJson, body: body);

  Future<void> deleteShopProduct(String id) =>
      _client.delete('/marketplace/shop/products/$id');
}
