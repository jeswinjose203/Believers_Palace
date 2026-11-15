import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/calendar_models.dart';

/// Result of scheduling local calendar notifications.
class CalendarNotificationSyncResult {
  final int scheduled;
  final bool notificationsGranted;
  final bool exactAlarmsGranted;

  const CalendarNotificationSyncResult({
    required this.scheduled,
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
  });

  bool get ready => notificationsGranted && exactAlarmsGranted;
}

class CalendarNotificationService {
  CalendarNotificationService._();
  static final instance = CalendarNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _taskIdBase = 100000;

  tz.Location get _ist => tz.getLocation('Asia/Kolkata');

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    _ready = true;
  }

  Future<({bool notifications, bool exactAlarms})> ensurePermissions() async {
    if (!_ready) await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    bool notifications = true;
    bool exact = true;
    if (androidImpl != null) {
      notifications = await androidImpl.requestNotificationsPermission() ?? true;
      exact = await androidImpl.requestExactAlarmsPermission() ?? true;
      if (!exact) {
        final can = await androidImpl.canScheduleExactNotifications();
        exact = can ?? false;
      }
    }
    return (notifications: notifications, exactAlarms: exact);
  }

  Future<CalendarNotificationSyncResult> rescheduleAll({
    required List<PersonalCalendarEvent> events,
    required List<CalendarTask> tasks,
  }) async {
    if (!_ready) await init();
    final perms = await ensurePermissions();
    await _plugin.cancelAll();
    var scheduled = 0;
    scheduled += await _scheduleEvents(events, exactAlarms: perms.exactAlarms);
    scheduled += await _scheduleTasks(tasks, exactAlarms: perms.exactAlarms);
    return CalendarNotificationSyncResult(
      scheduled: scheduled,
      notificationsGranted: perms.notifications,
      exactAlarmsGranted: perms.exactAlarms,
    );
  }

  Future<void> rescheduleForEvents(List<PersonalCalendarEvent> events) async {
    await rescheduleAll(events: events, tasks: const []);
  }

  /// Drops scheduled reminders when the user signs out.
  Future<void> clearForLogout() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  tz.TZDateTime _eventStartIst(PersonalCalendarEvent e) {
    return tz.TZDateTime.from(e.startAt, _ist);
  }

  tz.TZDateTime _nowIst() => tz.TZDateTime.now(_ist);

  Future<int> _scheduleEvents(
    List<PersonalCalendarEvent> events, {
    required bool exactAlarms,
  }) async {
    final now = _nowIst();
    final horizon = now.add(const Duration(days: 30));
    final timeFmt = DateFormat.jm();
    var id = 0;
    var count = 0;
    if (!exactAlarms) {
      debugPrint('Exact alarms not allowed — event reminders not scheduled');
      return 0;
    }
    const mode = AndroidScheduleMode.exactAllowWhileIdle;

    for (final e in events) {
      if (e.reminderMinutes.isEmpty) continue;
      final startIst = _eventStartIst(e);
      if (startIst.isBefore(now.subtract(const Duration(hours: 1))) ||
          startIst.isAfter(horizon)) {
        continue;
      }
      for (final mins in e.reminderMinutes) {
        final at = startIst.subtract(Duration(minutes: mins));
        if (!at.isAfter(now)) continue;
        final body = mins == 0
            ? 'Starting now (${timeFmt.format(startIst)})'
            : '$mins min before start (${timeFmt.format(startIst)})';
        try {
          await _plugin.zonedSchedule(
            id++,
            e.title,
            body,
            at,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'personal_calendar',
                'Calendar reminders',
                channelDescription: 'Reminders before personal calendar events',
                importance: Importance.max,
                priority: Priority.high,
                playSound: true,
                enableVibration: true,
              ),
            ),
            androidScheduleMode: mode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          count++;
          if (kDebugMode) {
            debugPrint(
              'Calendar reminder scheduled: "${e.title}" at $at (IST), $mins min before start',
            );
          }
        } catch (err, st) {
          debugPrint('Failed to schedule event reminder: $err\n$st');
        }
      }
    }
    return count;
  }

  Future<int> _scheduleTasks(
    List<CalendarTask> tasks, {
    required bool exactAlarms,
  }) async {
    final now = _nowIst();
    final horizon = now.add(const Duration(days: 30));
    var i = 0;
    var count = 0;
    if (!exactAlarms) {
      return 0;
    }
    const mode = AndroidScheduleMode.exactAllowWhileIdle;

    for (final t in tasks) {
      if (t.completed) continue;
      final dueIst = tz.TZDateTime.from(t.dueDate, _ist);
      if (!dueIst.isAfter(now) || dueIst.isAfter(horizon)) continue;
      try {
        await _plugin.zonedSchedule(
          _taskIdBase + i++,
          'Task due: ${t.title}',
          'Due ${dueIst.hour.toString().padLeft(2, '0')}:${dueIst.minute.toString().padLeft(2, '0')} IST',
          dueIst,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'calendar_tasks',
              'Task reminders',
              channelDescription: 'Alerts when a calendar task is due',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        count++;
      } catch (err, st) {
        debugPrint('Failed to schedule task reminder: $err\n$st');
      }
    }
    return count;
  }
}