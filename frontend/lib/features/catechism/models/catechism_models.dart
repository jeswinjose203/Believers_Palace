class CatechismClass {
  final String id;
  final String churchId;
  final String name;
  final String? description;
  final String level;
  final int? minAge;
  final int? maxAge;
  final String? teacherUserId;
  final String? teacherName;
  final List<ScheduleSlot> schedule;
  final String? location;
  final DateTime startDate;
  final DateTime endDate;
  final int capacity;
  final String status;
  final String? image;
  final int enrolledCount;
  final int availableSeats;
  final bool enrolled;

  CatechismClass({
    required this.id,
    required this.churchId,
    required this.name,
    this.description,
    required this.level,
    this.minAge,
    this.maxAge,
    this.teacherUserId,
    this.teacherName,
    this.schedule = const [],
    this.location,
    required this.startDate,
    required this.endDate,
    required this.capacity,
    required this.status,
    this.image,
    this.enrolledCount = 0,
    this.availableSeats = 0,
    this.enrolled = false,
  });

  factory CatechismClass.fromJson(Map<String, dynamic> json) => CatechismClass(
        id: json['id'] as String,
        churchId: json['churchId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        level: json['level'] as String,
        minAge: json['minAge'] as int?,
        maxAge: json['maxAge'] as int?,
        teacherUserId: json['teacherUserId'] as String?,
        teacherName: json['teacherName'] as String?,
        schedule: (json['schedule'] as List<dynamic>? ?? [])
            .map((e) => ScheduleSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
        location: json['location'] as String?,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        capacity: json['capacity'] as int,
        status: json['status'] as String,
        image: json['image'] as String?,
        enrolledCount: json['enrolledCount'] as int? ?? 0,
        availableSeats: json['availableSeats'] as int? ?? 0,
        enrolled: json['enrolled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'level': level,
        'minAge': minAge,
        'maxAge': maxAge,
        'teacherUserId': teacherUserId,
        'teacherName': teacherName,
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'location': location,
        'startDate': startDate.toIso8601String().split('T').first,
        'endDate': endDate.toIso8601String().split('T').first,
        'capacity': capacity,
        'status': status,
        'image': image,
      };
}

class ScheduleSlot {
  final String day;
  final String time;

  ScheduleSlot({required this.day, required this.time});

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) => ScheduleSlot(
        day: json['day'] as String? ?? '',
        time: json['time'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'day': day, 'time': time};
}

class CatechismEnrollment {
  final String id;
  final String classId;
  final String guardianId;
  final String studentName;
  final DateTime dateOfBirth;
  final String? notes;
  final String status;
  final String? className;
  final String? classLevel;
  final String? classStatus;

  CatechismEnrollment({
    required this.id,
    required this.classId,
    required this.guardianId,
    required this.studentName,
    required this.dateOfBirth,
    this.notes,
    required this.status,
    this.className,
    this.classLevel,
    this.classStatus,
  });

  factory CatechismEnrollment.fromJson(Map<String, dynamic> json) =>
      CatechismEnrollment(
        id: json['id'] as String,
        classId: json['classId'] as String,
        guardianId: json['guardianId'] as String,
        studentName: json['studentName'] as String,
        dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
        notes: json['notes'] as String?,
        status: json['status'] as String,
        className: json['className'] as String?,
        classLevel: json['classLevel'] as String?,
        classStatus: json['classStatus'] as String?,
      );

  Map<String, dynamic> toCreateJson() => {
        'studentName': studentName,
        'dateOfBirth': dateOfBirth.toIso8601String().split('T').first,
        'notes': notes,
      };
}

class CatechismSession {
  final String id;
  final String classId;
  final String title;
  final String? topic;
  final DateTime sessionDate;
  final String startTime;
  final String endTime;
  final String? notes;

  CatechismSession({
    required this.id,
    required this.classId,
    required this.title,
    this.topic,
    required this.sessionDate,
    required this.startTime,
    required this.endTime,
    this.notes,
  });

  factory CatechismSession.fromJson(Map<String, dynamic> json) => CatechismSession(
        id: json['id'] as String,
        classId: json['classId'] as String,
        title: json['title'] as String,
        topic: json['topic'] as String?,
        sessionDate: DateTime.parse(json['sessionDate'] as String),
        startTime: json['startTime'] as String,
        endTime: json['endTime'] as String,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'topic': topic,
        'sessionDate': sessionDate.toIso8601String().split('T').first,
        'startTime': startTime,
        'endTime': endTime,
        'notes': notes,
      };
}

String levelLabel(String level) {
  switch (level) {
    case 'first_communion':
      return 'First Communion';
    case 'confirmation':
      return 'Confirmation';
    case 'baptism_prep':
      return 'Baptism prep';
    case 'sunday_school':
      return 'Sunday school';
    case 'adult':
      return 'Adult';
    default:
      return 'Other';
  }
}