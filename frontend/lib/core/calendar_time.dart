import 'package:intl/intl.dart';

/// Calendar date helpers using the device local timezone (set device TZ to India
/// for IST). Comparisons always use local calendar days, not UTC fields.
class CalendarTime {
  CalendarTime._();

  static String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static bool sameCalendarDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final al = a.toLocal();
    final bl = b.toLocal();
    return al.year == bl.year && al.month == bl.month && al.day == bl.day;
  }

  static bool onCalendarDay(DateTime? instant, DateTime day) {
    if (instant == null) return false;
    final l = instant.toLocal();
    return l.year == day.year && l.month == day.month && l.day == day.day;
  }

  static DateTime startOfLocalDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// Interpret wall-clock parts as local, then convert to UTC for the API.
  static String localDateTimeToUtcIso(DateTime local) =>
      local.toUtc().toIso8601String();

  static String localDateToYmd(DateTime local) => ymd(local);
}