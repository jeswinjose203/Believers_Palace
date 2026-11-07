class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? unit;
  final String? profilePic;
  final String role;
  final String? churchId;
  final bool emailVerified;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.unit,
    this.profilePic,
    required this.role,
    this.churchId,
    this.emailVerified = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        unit: json['unit'] as String?,
        profilePic: json['profilePic'] as String?,
        role: json['role'] as String,
        churchId: json['churchId'] as String?,
        emailVerified: (json['emailVerified'] as bool?) ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'unit': unit,
        'profilePic': profilePic,
        'role': role,
        'churchId': churchId,
        'emailVerified': emailVerified,
        'createdAt': createdAt.toIso8601String(),
      };
}

class AuthResponse {
  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final User user;

  AuthResponse({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    required this.user,
  });

  /// Backward-compatible alias for the access token.
  String get token => accessToken;

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        // Prefer accessToken; fall back to the legacy `token` field.
        accessToken: (json['accessToken'] ?? json['token']) as String,
        refreshToken: json['refreshToken'] as String?,
        expiresIn: json['expiresIn'] as int?,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class Pagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) => Pagination(
        page: json['page'] as int,
        limit: json['limit'] as int,
        total: json['total'] as int,
        totalPages: json['totalPages'] as int,
      );
}

class PaginatedResponse<T> {
  final List<T> data;
  final Pagination pagination;

  PaginatedResponse({required this.data, required this.pagination});

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      PaginatedResponse(
        data: (json['data'] as List)
            .map((e) => fromJson(e as Map<String, dynamic>))
            .toList(),
        pagination: Pagination.fromJson(json['pagination'] as Map<String, dynamic>),
      );
}

class PriestDetails {
  final String? name;
  final String? phone;
  final String? email;
  final String? profilePic;

  PriestDetails({this.name, this.phone, this.email, this.profilePic});

  factory PriestDetails.fromJson(Map<String, dynamic> json) => PriestDetails(
        name: json['name'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        profilePic: json['profilePic'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'profilePic': profilePic,
      };
}

class Church {
  final String id;
  final String name;
  final String? description;
  final String? about;
  final String? address;
  final String? phone;
  final String? email;
  final String? logo;
  final List<String> images;
  final double? latitude;
  final double? longitude;
  final PriestDetails? priest;
  final PriestDetails? associatePriest;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Church({
    required this.id,
    required this.name,
    this.description,
    this.about,
    this.address,
    this.phone,
    this.email,
    this.logo,
    this.images = const [],
    this.latitude,
    this.longitude,
    this.priest,
    this.associatePriest,
    this.createdAt,
    this.updatedAt,
  });

  factory Church.fromJson(Map<String, dynamic> json) => Church(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        about: json['about'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        logo: json['logo'] as String?,
        images: (json['images'] as List?)?.map((e) => e as String).toList() ??
            const [],
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        priest: json['priest'] != null
            ? PriestDetails.fromJson(json['priest'] as Map<String, dynamic>)
            : null,
        associatePriest: json['associatePriest'] != null
            ? PriestDetails.fromJson(json['associatePriest'] as Map<String, dynamic>)
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'about': about,
        'address': address,
        'phone': phone,
        'email': email,
        'logo': logo,
        'images': images,
        'latitude': latitude,
        'longitude': longitude,
        'priest': priest?.toJson(),
        'associatePriest': associatePriest?.toJson(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };
}

class Announcement {
  final String id;
  final String churchId;
  final String title;
  final String content;
  final String? image;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Announcement({
    required this.id,
    required this.churchId,
    required this.title,
    required this.content,
    this.image,
    this.publishedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        image: json['image'] as String?,
        publishedAt: json['publishedAt'] != null
            ? DateTime.tryParse(json['publishedAt'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'content': content,
        'image': image,
        'publishedAt': publishedAt?.toIso8601String(),
      };
}

class Hall {
  final String id;
  final String churchId;
  final String name;
  final String? description;
  final int? capacity;
  final String? location;
  final List<String> images;
  final List<String> amenities;
  final double? price;
  final DateTime? createdAt;

  Hall({
    required this.id,
    required this.churchId,
    required this.name,
    this.description,
    this.capacity,
    this.location,
    this.images = const [],
    this.amenities = const [],
    this.price,
    this.createdAt,
  });

  factory Hall.fromJson(Map<String, dynamic> json) => Hall(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        capacity: json['capacity'] as int?,
        location: json['location'] as String?,
        images: (json['images'] as List?)?.cast<String>() ?? const [],
        amenities: (json['amenities'] as List?)?.cast<String>() ?? const [],
        price: (json['price'] as num?)?.toDouble(),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'capacity': capacity,
        'location': location,
        'images': images,
        'amenities': amenities,
        'price': price,
      };
}

class Booking {
  final String id;
  final String churchId;
  final String hallId;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final String? purpose;
  final String? notes;
  final String status;
  final String? adminNotes;
  final String? cancellationReason;
  final DateTime? createdAt;
  final BookingRequester? user;

  Booking({
    required this.id,
    required this.churchId,
    required this.hallId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    this.purpose,
    this.notes,
    required this.status,
    this.adminNotes,
    this.cancellationReason,
    this.createdAt,
    this.user,
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        hallId: json['hallId'] as String,
        userId: json['userId'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        purpose: json['purpose'] as String?,
        notes: json['notes'] as String?,
        status: json['status'] as String,
        adminNotes: json['adminNotes'] as String?,
        cancellationReason: json['cancellationReason'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        user: json['user'] != null
            ? BookingRequester.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'hallId': hallId,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'purpose': purpose,
        'notes': notes,
      };
}

/// Public profile of the user who made a booking (admin-facing).
class BookingRequester {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? profilePic;

  BookingRequester({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.profilePic,
  });

  factory BookingRequester.fromJson(Map<String, dynamic> json) =>
      BookingRequester(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        profilePic: json['profilePic'] as String?,
      );
}

class Event {
  final String id;
  final String churchId;
  final String title;
  final String? description;
  final String? location;
  final DateTime startDate;
  final DateTime? endDate;
  final String? image;
  final int? capacity;
  final bool? registrationRequired;
  final DateTime? createdAt;

  /// Whether the signed-in user is registered (only set on list responses).
  final bool registered;

  Event({
    required this.id,
    required this.churchId,
    required this.title,
    this.description,
    this.location,
    required this.startDate,
    this.endDate,
    this.image,
    this.capacity,
    this.registrationRequired,
    this.createdAt,
    this.registered = false,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        location: json['location'] as String?,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: json['endDate'] != null
            ? DateTime.tryParse(json['endDate'] as String)
            : null,
        image: json['image'] as String?,
        capacity: json['capacity'] as int?,
        registrationRequired: json['registrationRequired'] as bool?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        registered: json['registered'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'location': location,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'image': image,
        'capacity': capacity,
        'registrationRequired': registrationRequired,
      };
}

class EventRegistration {
  final String id;
  final String eventId;
  final String? userId;
  final String? attendeeName;
  final String? attendeeEmail;
  final String? attendeePhone;
  final String? notes;
  final DateTime? createdAt;

  EventRegistration({
    required this.id,
    required this.eventId,
    this.userId,
    this.attendeeName,
    this.attendeeEmail,
    this.attendeePhone,
    this.notes,
    this.createdAt,
  });

  factory EventRegistration.fromJson(Map<String, dynamic> json) =>
      EventRegistration(
        id: json['id'] as String,
        eventId: json['eventId'] as String,
        userId: json['userId'] as String?,
        attendeeName: json['attendeeName'] as String?,
        attendeeEmail: json['attendeeEmail'] as String?,
        attendeePhone: json['attendeePhone'] as String?,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'attendeeName': attendeeName,
        'attendeeEmail': attendeeEmail,
        'attendeePhone': attendeePhone,
        'notes': notes,
      };
}

class CemeteryPlot {
  final String id;
  final String churchId;
  final String plotNumber;
  final String? section;
  final String? locationDescription;
  final String status;
  final String? notes;
  final DateTime? createdAt;

  CemeteryPlot({
    required this.id,
    required this.churchId,
    required this.plotNumber,
    this.section,
    this.locationDescription,
    required this.status,
    this.notes,
    this.createdAt,
  });

  factory CemeteryPlot.fromJson(Map<String, dynamic> json) => CemeteryPlot(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        plotNumber: json['plotNumber'] as String,
        section: json['section'] as String?,
        locationDescription: json['locationDescription'] as String?,
        status: json['status'] as String,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'plotNumber': plotNumber,
        'section': section,
        'locationDescription': locationDescription,
        'status': status,
        'notes': notes,
      };
}

class CemeteryServiceRequest {
  final String id;
  final String churchId;
  final String userId;
  final String type;
  final String status;
  final String fullName;
  final String? contactPhone;
  final String? contactEmail;
  final String? deceasedName;
  final DateTime? requestedDate;
  final String? plotId;
  final String? description;
  final String? notes;
  final String? adminNotes;
  final DateTime? scheduledDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CemeteryServiceRequest({
    required this.id,
    required this.churchId,
    required this.userId,
    required this.type,
    required this.status,
    required this.fullName,
    this.contactPhone,
    this.contactEmail,
    this.deceasedName,
    this.requestedDate,
    this.plotId,
    this.description,
    this.notes,
    this.adminNotes,
    this.scheduledDate,
    this.createdAt,
    this.updatedAt,
  });

  factory CemeteryServiceRequest.fromJson(Map<String, dynamic> json) =>
      CemeteryServiceRequest(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        userId: json['userId'] as String,
        type: json['type'] as String,
        status: json['status'] as String,
        fullName: json['fullName'] as String,
        contactPhone: json['contactPhone'] as String?,
        contactEmail: json['contactEmail'] as String?,
        deceasedName: json['deceasedName'] as String?,
        requestedDate: json['requestedDate'] != null
            ? DateTime.tryParse(json['requestedDate'] as String)
            : null,
        plotId: json['plotId'] as String?,
        description: json['description'] as String?,
        notes: json['notes'] as String?,
        adminNotes: json['adminNotes'] as String?,
        scheduledDate: json['scheduledDate'] != null
            ? DateTime.tryParse(json['scheduledDate'] as String)
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'fullName': fullName,
        'contactPhone': contactPhone,
        'contactEmail': contactEmail,
        'deceasedName': deceasedName,
        'requestedDate': requestedDate?.toIso8601String(),
        'plotId': plotId,
        'description': description,
        'notes': notes,
      };
}

class Certificate {
  final String id;
  final String userId;
  final String uploadedByUserId;
  final String type;
  final String certificateNumber;
  final String fullName;
  final DateTime? issueDate;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? notes;
  final DateTime? createdAt;

  Certificate({
    required this.id,
    required this.userId,
    required this.uploadedByUserId,
    required this.type,
    required this.certificateNumber,
    required this.fullName,
    this.issueDate,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    this.notes,
    this.createdAt,
  });

  factory Certificate.fromJson(Map<String, dynamic> json) => Certificate(
        id: json['id'] as String,
        userId: json['userId'] as String,
        uploadedByUserId: json['uploadedByUserId'] as String,
        type: json['type'] as String,
        certificateNumber: json['certificateNumber'] as String,
        fullName: json['fullName'] as String,
        issueDate: json['issueDate'] != null
            ? DateTime.tryParse(json['issueDate'] as String)
            : null,
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String,
        fileSize: json['fileSize'] as int,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );
}

class ChatMessage {
  final String id;
  final String eventId;

  /// Monotonic cursor used for paging and polling.
  final int seq;
  final String? userId;
  final String authorName;
  final String? authorPic;
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.eventId,
    this.seq = 0,
    this.userId,
    required this.authorName,
    this.authorPic,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        eventId: json['eventId'] as String,
        seq: (json['seq'] as num?)?.toInt() ?? 0,
        userId: json['userId'] as String?,
        authorName: json['authorName'] as String? ?? 'User',
        authorPic: json['authorPic'] as String?,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class UserStats {
  final int total;
  final Map<String, int> byRole;

  UserStats({required this.total, required this.byRole});

  /// Returns the count for [role], defaulting to 0 when the backend omitted a
  /// role with no users.
  int countFor(String role) => byRole[role] ?? 0;

  factory UserStats.fromJson(Map<String, dynamic> json) {
    final raw = (json['byRole'] as Map<String, dynamic>?) ?? const {};
    return UserStats(
      total: (json['total'] as int?) ?? 0,
      byRole: raw.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }
}

class ErrorResponse {
  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  ErrorResponse({required this.message, this.code, this.details});

  factory ErrorResponse.fromJson(Map<String, dynamic> json) => ErrorResponse(
        message: json['message'] as String,
        code: json['code'] as String?,
        details: json['details'] as Map<String, dynamic>?,
      );
}

/// A window of chat messages (oldest first) from the cursor API.
class ChatCursorPage {
  final List<ChatMessage> data;
  final bool hasMore;

  ChatCursorPage({required this.data, required this.hasMore});

  factory ChatCursorPage.fromJson(Map<String, dynamic> json) => ChatCursorPage(
        data: (json['data'] as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: (json['hasMore'] as bool?) ?? false,
      );
}
