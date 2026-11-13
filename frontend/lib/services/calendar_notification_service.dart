import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
 
import '../models/calendar_models.dart';
 
class CalendarNotificationService {
  CalendarNotificationService._();
  static final instance = CalendarNotificationService._();
 
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
 
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    _ready = true;
  }
 
  Future<void> rescheduleForEvents(List<PersonalCalendarEvent> events) async {
    if (!_ready) await init();
    await _plugin.cancelAll();
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 30));
    var id = 0;
    for (final e in events) {
      if (e.startAt.isBefore(now) || e.startAt.isAfter(horizon)) continue;
      for (final mins in e.reminderMinutes) {
        final at = e.startAt.subtract(Duration(minutes: mins));
        if (at.isBefore(now)) continue;
        await _plugin.zonedSchedule(
          id++,
          e.title,
          'Starting in $mins minutes',
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
}
 