
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import 'api_service.dart';
import 'calendar_notification_service.dart';

/// Loads calendar data from the API and schedules on-device reminders.
Future<CalendarNotificationSyncResult> syncCalendarReminders(
  WidgetRef ref,
) async {
  final api = ref.read(apiServiceProvider);
  final events = await api.listCalendarEvents(limit: 200);
  final tasks = await api.listCalendarTasks(limit: 200);
  return CalendarNotificationService.instance.rescheduleAll(
    events: events.data,
    tasks: tasks.data,
  );
}

void showCalendarReminderPermissionHint(
  BuildContext context,
  CalendarNotificationSyncResult result,
) {
  if (result.ready && result.scheduled > 0) return;
  final parts = <String>[];
  if (!result.notificationsGranted) {
    parts.add(context.tr('Allow notifications for Believers Palace'));
  }
  if (!result.exactAlarmsGranted) {
    parts.add(context.tr('Open Settings → Alarms & reminders (or Special app access) and allow exact alarms for this app'));
  }
  if (result.ready && result.scheduled == 0) {
    parts.add(context.tr('No upcoming reminders were scheduled (check event time and that the reminder is in the future)'));
  }
  if (parts.isEmpty) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(parts.join('. ')),
      duration: const Duration(seconds: 6),
    ),
  );
}