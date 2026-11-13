class CalendarPreferences {
  final String theme;
  final String dateFormat;
  final String weekStartsOn;
  final String holidayCountry;
  final Map<String, String> categoryColors;
 
  CalendarPreferences({
    required this.theme,
    required this.dateFormat,
    required this.weekStartsOn,
    required this.holidayCountry,
    required this.categoryColors,
  });
 
  factory CalendarPreferences.fromJson(Map<String, dynamic> json) =>
      CalendarPreferences(
        theme: json['theme'] as String? ?? 'system',
        dateFormat: json['dateFormat'] as String? ?? 'dmy',
        weekStartsOn: json['weekStartsOn'] as String? ?? 'monday',
        holidayCountry: json['holidayCountry'] as String? ?? 'IN',
        categoryColors: Map<String, String>.from(
          (json['categoryColors'] as Map<String, dynamic>? ?? {}),
        ),
      );
 
  Map<String, dynamic> toJson() => {
        'theme': theme,
        'dateFormat': dateFormat,
        'weekStartsOn': weekStartsOn,
        'holidayCountry': holidayCountry,
        if (categoryColors.isNotEmpty) 'categoryColors': categoryColors,
      };
}
 
class PersonalCalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String category;
  final String? color;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final String recurrence;
  final int recurrenceInterval;
  final DateTime? recurrenceUntil;
  final List<int> reminderMinutes;
 
  PersonalCalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    this.color,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.recurrence,
    required this.recurrenceInterval,
    this.recurrenceUntil,
    required this.reminderMinutes,
  });
 
  factory PersonalCalendarEvent.fromJson(Map<String, dynamic> json) =>
      PersonalCalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        category: json['category'] as String? ?? 'personal',
        color: json['color'] as String?,
        startAt: DateTime.parse(json['startAt'] as String),
        endAt: DateTime.parse(json['endAt'] as String),
        allDay: json['allDay'] as bool? ?? false,
        recurrence: json['recurrence'] as String? ?? 'none',
        recurrenceInterval: json['recurrenceInterval'] as int? ?? 1,
        recurrenceUntil: json['recurrenceUntil'] != null
            ? DateTime.parse(json['recurrenceUntil'] as String)
            : null,
        reminderMinutes: (json['reminderMinutes'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}
 
class CalendarTask {
  final String id;
  final String title;
  final String? description;
  final DateTime dueDate;
  final bool completed;
 
  CalendarTask({
    required this.id,
    required this.title,
    this.description,
    required this.dueDate,
    required this.completed,
  });
 
  factory CalendarTask.fromJson(Map<String, dynamic> json) => CalendarTask(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        dueDate: DateTime.parse(json['dueDate'] as String),
        completed: json['completed'] as bool? ?? false,
      );
}
 
class CalendarGoal {
  final String id;
  final String title;
  final String? description;
  final int targetDays;
  final String trackingMode;
  final String status;
  final int checkInCount;
  final int currentStreak;
 
  CalendarGoal({
    required this.id,
    required this.title,
    this.description,
    required this.targetDays,
    required this.trackingMode,
    required this.status,
    required this.checkInCount,
    required this.currentStreak,
  });
 
  factory CalendarGoal.fromJson(Map<String, dynamic> json) => CalendarGoal(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        targetDays: json['targetDays'] as int,
        trackingMode: json['trackingMode'] as String? ?? 'total',
        status: json['status'] as String? ?? 'active',
        checkInCount: json['checkInCount'] as int? ?? 0,
        currentStreak: json['currentStreak'] as int? ?? 0,
      );
 
  double get progressFraction =>
      targetDays == 0 ? 0 : (checkInCount / targetDays).clamp(0, 1);
}
 
class CalendarAchievement {
  final String code;
  final String title;
  final String description;
  final String icon;
  final bool unlocked;
  final String? goalId;
 
  CalendarAchievement({
    required this.code,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
    this.goalId,
  });
 
  factory CalendarAchievement.fromJson(Map<String, dynamic> json) =>
      CalendarAchievement(
        code: json['code'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        icon: json['icon'] as String? ?? 'emoji_events',
        unlocked: json['unlocked'] as bool? ?? false,
        goalId: json['goalId'] as String?,
      );
}
 
class ScheduleItem {
  final String kind;
  final String? id;
  final String? title;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? dueDate;
  final DateTime? date;
  final String? category;
  final String? color;
  final bool? completed;
  final String? status;
  final String? goalId;
  final bool? checkedInToday;
 
  ScheduleItem({
    required this.kind,
    this.id,
    this.title,
    this.startAt,
    this.endAt,
    this.dueDate,
    this.date,
    this.category,
    this.color,
    this.completed,
    this.status,
    this.goalId,
    this.checkedInToday,
  });
 
  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        kind: json['kind'] as String,
        id: json['id'] as String? ??
            json['bookingId'] as String? ??
            json['eventId'] as String?,
        title: json['title'] as String? ?? json['name'] as String?,
        startAt: json['startAt'] != null
            ? DateTime.parse(json['startAt'] as String)
            : json['startDate'] != null
                ? DateTime.parse(json['startDate'] as String)
                : null,
        endAt: json['endAt'] != null
            ? DateTime.parse(json['endAt'] as String)
            : null,
        dueDate: json['dueDate'] != null
            ? DateTime.parse(json['dueDate'] as String)
            : null,
        date: json['date'] != null
            ? DateTime.parse(json['date'] as String)
            : null,
        category: json['category'] as String?,
        color: json['color'] as String?,
        completed: json['completed'] as bool?,
        status: json['status'] as String?,
        goalId: json['goalId'] as String?,
        checkedInToday: json['checkedInToday'] as bool?,
      );
}
 
class CheckInResponse {
  final CalendarGoal goal;
  final List<CalendarAchievement> newAchievements;
 
  CheckInResponse({
    required this.goal,
    required this.newAchievements,
  });
 
  factory CheckInResponse.fromJson(Map<String, dynamic> json) => CheckInResponse(
        goal: CalendarGoal.fromJson(json['goal'] as Map<String, dynamic>),
        newAchievements: (json['newAchievements'] as List<dynamic>? ?? [])
            .map((e) => CalendarAchievement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
 