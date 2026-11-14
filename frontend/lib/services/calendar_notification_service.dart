import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/calendar_models.dart';

class CalendarNotificationService {
  CalendarNotificationService._();
  static final instance = CalendarNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _taskIdBase = 100000;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
    _ready = true;
  }

  Future<void> rescheduleAll({
    required List<PersonalCalendarEvent> events,
    required List<CalendarTask> tasks,
  }) async {
    if (!_ready) await init();
    await _plugin.cancelAll();
    await _scheduleEvents(events);
    await _scheduleTasks(tasks);
  }

  /// Kept for older call sites.
  Future<void> rescheduleForEvents(List<PersonalCalendarEvent> events) =>
      rescheduleAll(events: events, tasks: const []);

  Future<void> _scheduleEvents(List<PersonalCalendarEvent> events) async {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 30));
    var id = 0;
    for (final e in events) {
      if (e.reminderMinutes.isEmpty) continue;
      final startLocal = e.startAt.toLocal();
      if (startLocal.isBefore(now.subtract(const Duration(hours: 1))) ||
          startLocal.isAfter(horizon)) {
        continue;
      }
      for (final mins in e.reminderMinutes) {
        final at = startLocal.subtract(Duration(minutes: mins));
        if (at.isBefore(now)) continue;
        await _plugin.zonedSchedule(
          id++,
          e.title,
          mins == 0 ? 'Starting now' : 'Starting in $mins minutes',
          tz.TZDateTime.from(at, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'personal_calendar',
              'Calendar reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  Future<void> _scheduleTasks(List<CalendarTask> tasks) async {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 30));
    var i = 0;
    for (final t in tasks) {
      if (t.completed) continue;
      final dueLocal = t.dueDate.toLocal();
      if (dueLocal.isBefore(now) || dueLocal.isAfter(horizon)) continue;
      await _plugin.zonedSchedule(
        _taskIdBase + i++,
        'Task due: ${t.title}',
        'Due ${dueLocal.hour.toString().padLeft(2, '0')}:${dueLocal.minute.toString().padLeft(2, '0')}',
        tz.TZDateTime.from(dueLocal, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'calendar_tasks',
            'Task reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}