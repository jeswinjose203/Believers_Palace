import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
 
import '../models/calendar_models.dart';
import '../services/api_service.dart';
 
class TodayScheduleCard extends ConsumerStatefulWidget {
  const TodayScheduleCard({super.key});
 
  @override
  ConsumerState<TodayScheduleCard> createState() => _TodayScheduleCardState();
}
 
class _TodayScheduleCardState extends ConsumerState<TodayScheduleCard> {
  Future<List<ScheduleItem>>? _future;
 
  Future<List<ScheduleItem>> _load() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 2));
    return ref.read(apiServiceProvider).getCalendarSchedule(start, end);
  }
 
  @override
  void initState() {
    super.initState();
    _future = _load();
  }
 
  Future<void> _checkIn(String goalId) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await ref.read(apiServiceProvider).checkInGoal(goalId, today);
    setState(() => _future = _load());
  }
 
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScheduleItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final today = DateTime.now();
        bool isToday(ScheduleItem i) {
          DateTime? d = i.startAt ?? i.dueDate ?? i.date;
          if (d == null) return false;
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }
 
        final items = snapshot.data!.where(isToday).take(6).toList();
        final goalsDue = snapshot.data!
            .where((i) => i.kind == 'goal_checkin_due' && isToday(i) && i.checkedInToday != true)
            .toList();
 
        if (items.isEmpty && goalsDue.isEmpty) return const SizedBox.shrink();
 
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Today's schedule", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...items.map((i) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.title ?? i.kind),
                    )),
                ...goalsDue.map((g) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Goal: ${g.title}'),
                      trailing: TextButton(
                        onPressed: g.goalId == null ? null : () => _checkIn(g.goalId!),
                        child: const Text('Check in'),
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}
