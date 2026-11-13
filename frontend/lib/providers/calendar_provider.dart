import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../models/calendar_models.dart';
import '../services/api_service.dart';
 
enum CalendarViewMode { month, week, day }
 
class CalendarUiState {
  final CalendarViewMode viewMode;
  final DateTime focusedDay;
  final DateTime selectedDay;
  final List<ScheduleItem> schedule;
  final CalendarPreferences? preferences;
  final bool loading;
 
  CalendarUiState({
    required this.viewMode,
    required this.focusedDay,
    required this.selectedDay,
    required this.schedule,
    this.preferences,
    this.loading = false,
  });
 
  CalendarUiState copyWith({
    CalendarViewMode? viewMode,
    DateTime? focusedDay,
    DateTime? selectedDay,
    List<ScheduleItem>? schedule,
    CalendarPreferences? preferences,
    bool? loading,
  }) =>
      CalendarUiState(
        viewMode: viewMode ?? this.viewMode,
        focusedDay: focusedDay ?? this.focusedDay,
        selectedDay: selectedDay ?? this.selectedDay,
        schedule: schedule ?? this.schedule,
        preferences: preferences ?? this.preferences,
        loading: loading ?? this.loading,
      );
}
 
class CalendarNotifier extends StateNotifier<CalendarUiState> {
  CalendarNotifier(this._api)
      : super(CalendarUiState(
          viewMode: CalendarViewMode.month,
          focusedDay: DateTime.now(),
          selectedDay: DateTime.now(),
          schedule: const [],
        ));
 
  final ApiService _api;
 
  Future<void> bootstrap() async {
    state = state.copyWith(loading: true);
    try {
      final prefs = await _api.getCalendarPreferences();
      state = state.copyWith(preferences: prefs);
      await refreshSchedule();
    } finally {
      state = state.copyWith(loading: false);
    }
  }
 
  Future<void> refreshSchedule() async {
    final from = DateTime(state.focusedDay.year, state.focusedDay.month, 1)
        .subtract(const Duration(days: 7));
    final to = DateTime(state.focusedDay.year, state.focusedDay.month + 1, 1)
        .add(const Duration(days: 37));
    final items = await _api.getCalendarSchedule(from, to);
    state = state.copyWith(schedule: items);
  }
 
  void setViewMode(CalendarViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }
 
  void selectDay(DateTime day) {
    state = state.copyWith(selectedDay: day, focusedDay: day);
  }
}
 
final calendarProvider =
    StateNotifierProvider<CalendarNotifier, CalendarUiState>((ref) {
  return CalendarNotifier(ref.watch(apiServiceProvider));
});