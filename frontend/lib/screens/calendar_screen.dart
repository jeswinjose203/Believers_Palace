import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
 
import '../models/calendar_models.dart';
import '../providers/calendar_provider.dart';
import '../services/api_service.dart';
import '../services/calendar_notification_service.dart';
 
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
 
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}
 
class _CalendarScreenState extends ConsumerState<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _search = '';
  List<CalendarTask> _tasks = [];
  List<CalendarGoal> _goals = [];
  List<CalendarAchievement> _achievements = [];
 
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }
 
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
 
  Future<void> _loadAll() async {
    await ref.read(calendarProvider.notifier).bootstrap();
    await _loadSideData();
    await _syncNotifications();
  }
 
  Future<void> _loadSideData() async {
    final api = ref.read(apiServiceProvider);
    final tasks = await api.listCalendarTasks();
    final goals = await api.listCalendarGoals();
    final achievements = await api.listCalendarAchievements();
    if (!mounted) return;
    setState(() {
      _tasks = tasks.data;
      _goals = goals.data;
      _achievements = achievements;
    });
  }
 
  Future<void> _syncNotifications() async {
    final api = ref.read(apiServiceProvider);
    final events = await api.listCalendarEvents(limit: 100);
    await CalendarNotificationService.instance
        .rescheduleForEvents(events.data);
  }
 
  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
 
  List<ScheduleItem> _itemsForDay(DateTime day) {
    final ui = ref.read(calendarProvider);
    final same = (DateTime? d) =>
        d != null && d.year == day.year && d.month == day.month && d.day == day.day;
    return ui.schedule.where((i) {
      if (_search.isNotEmpty &&
          (i.title ?? '').toLowerCase().contains(_search.toLowerCase()) ==
              false) {
        return false;
      }
      return same(i.startAt) || same(i.dueDate) || same(i.date);
    }).toList()
      ..sort((a, b) {
        final at = a.startAt ?? a.dueDate ?? a.date ?? DateTime(0);
        final bt = b.startAt ?? b.dueDate ?? b.date ?? DateTime(0);
        return at.compareTo(bt);
      });
  }
 
  Future<void> _addEvent() async {
    final title = TextEditingController();
    final desc = TextEditingController();
    var category = 'personal';
  DateTime start = DateTime.now();
  DateTime end = start.add(const Duration(hours: 1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
                DropdownButtonFormField<String>(
                  value: category,
                  items: const [
                    DropdownMenuItem(value: 'personal', child: Text('Personal')),
                    DropdownMenuItem(value: 'work', child: Text('Work')),
                    DropdownMenuItem(value: 'family', child: Text('Family')),
                    DropdownMenuItem(value: 'meetings', child: Text('Meetings')),
                  ],
                  onChanged: (v) => setSt(() => category = v ?? 'personal'),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await ref.read(apiServiceProvider).createCalendarEvent({
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'category': category,
        'startAt': start.toUtc().toIso8601String(),
        'endAt': end.toUtc().toIso8601String(),
        'recurrence': 'none',
        'reminderMinutes': [15],
      });
      await ref.read(calendarProvider.notifier).refreshSchedule();
      await _syncNotifications();
      _toast('Event created');
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _addTask() async {
    final title = TextEditingController();
    var due = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New task'),
        content: TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).createCalendarTask({
        'title': title.text.trim(),
        'dueDate': DateTime(due.year, due.month, due.day).toUtc().toIso8601String(),
      });
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      _toast('Task added');
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _addGoal() async {
    final title = TextEditingController();
    final target = TextEditingController(text: '7');
    var mode = 'total';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: target, decoration: const InputDecoration(labelText: 'Target days'), keyboardType: TextInputType.number),
              DropdownButtonFormField<String>(
                value: mode,
                items: const [
                  DropdownMenuItem(value: 'total', child: Text('Total check-ins')),
                  DropdownMenuItem(value: 'streak', child: Text('Streak')),
                ],
                onChanged: (v) => setSt(() => mode = v ?? 'total'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiServiceProvider).createCalendarGoal({
        'title': title.text.trim(),
        'targetDays': int.tryParse(target.text) ?? 7,
        'trackingMode': mode,
      });
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      _toast('Goal created');
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _checkInGoal(CalendarGoal g) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final resp = await ref.read(apiServiceProvider).checkInGoal(g.id, today);
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      if (resp.newAchievements.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Achievement unlocked!'),
            content: Text(resp.newAchievements.map((a) => a.title).join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nice'))],
          ),
        );
      }
    } catch (e) {
      _toast('$e');
    }
  }
 
  Widget _buildCalendarTab() {
    final ui = ref.watch(calendarProvider);
    final weekStart = ui.preferences?.weekStartsOn == 'sunday'
        ? StartingDayOfWeek.sunday
        : StartingDayOfWeek.monday;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SegmentedButton<CalendarViewMode>(
                segments: const [
                  ButtonSegment(value: CalendarViewMode.month, label: Text('Month')),
                  ButtonSegment(value: CalendarViewMode.week, label: Text('Week')),
                  ButtonSegment(value: CalendarViewMode.day, label: Text('Day')),
                ],
                selected: {ui.viewMode},
                onSelectionChanged: (s) =>
                    ref.read(calendarProvider.notifier).setViewMode(s.first),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.add), onPressed: _addEvent),
            ],
          ),
        ),
        if (ui.viewMode == CalendarViewMode.month)
          TableCalendar(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: ui.focusedDay,
            selectedDayPredicate: (d) => isSameDay(d, ui.selectedDay),
            startingDayOfWeek: weekStart,
            eventLoader: (day) => _itemsForDay(day),
            onDaySelected: (sel, focus) {
              ref.read(calendarProvider.notifier).selectDay(sel);
              if (ui.viewMode != CalendarViewMode.month) return;
              _showDaySheet(sel);
            },
            calendarStyle: const CalendarStyle(markersMaxCount: 3),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('Upcoming (7 days)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._upcoming(ui.schedule),
                const Divider(height: 24),
                Text('${DateFormat.yMMMd().format(ui.selectedDay)}', style: Theme.of(context).textTheme.titleMedium),
                ..._itemsForDay(ui.selectedDay).map(_scheduleTile),
              ],
            ),
          ),
        ),
      ],
    );
  }
 
  List<Widget> _upcoming(List<ScheduleItem> all) {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 7));
    final items = all.where((i) {
      final t = i.startAt ?? i.dueDate ?? i.date;
      return t != null && t.isAfter(now.subtract(const Duration(hours: 1))) && t.isBefore(end);
    }).take(12);
    if (items.isEmpty) {
      return [const Text('Nothing scheduled')];
    }
    return items.map(_scheduleTile).toList();
  }
 
  Widget _scheduleTile(ScheduleItem i) {
    Color? accent;
    if (i.color != null) {
      accent = _parseColor(i.color!);
    }
    final subtitle = switch (i.kind) {
      'booking' => 'Hall booking • ${i.status ?? ''}',
      'church_event' => 'Church event',
      'holiday' => 'Public holiday',
      'task' => 'Task',
      'goal_checkin_due' => i.checkedInToday == true ? 'Checked in' : 'Tap goal tab to check in',
      _ => i.category ?? 'Personal',
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: accent ?? Theme.of(context).colorScheme.primaryContainer,
        child: Icon(_iconFor(i.kind), size: 18),
      ),
      title: Text(i.title ?? 'Untitled'),
      subtitle: Text(subtitle),
      onTap: i.kind == 'personal_event' && i.id != null
          ? () => _deletePersonalEvent(i.id!)
          : null,
    );
  }
 
  IconData _iconFor(String kind) => switch (kind) {
        'booking' => Icons.meeting_room,
        'church_event' => Icons.church,
        'holiday' => Icons.celebration,
        'task' => Icons.check_box_outlined,
        'goal_checkin_due' => Icons.flag,
        _ => Icons.event,
      };
 
  Color? _parseColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) {
      return Color(int.parse('FF$h', radix: 16));
    }
    return null;
  }
 
  Future<void> _deletePersonalEvent(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteCalendarEvent(id);
    await ref.read(calendarProvider.notifier).refreshSchedule();
  }
 
  void _showDaySheet(DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(DateFormat.yMMMEd().format(day), style: Theme.of(context).textTheme.titleLarge),
            ..._itemsForDay(day).map(_scheduleTile),
          ],
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(calendarProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Calendar'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Calendar'),
            Tab(text: 'Tasks'),
            Tab(text: 'Goals'),
            Tab(text: 'Trophies'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () async {
              final q = await showSearch<String?>(
                context: context,
                delegate: _CalendarSearchDelegate(_search),
              );
              if (q != null) setState(() => _search = q);
            },
          ),
        ],
      ),
      body: ui.loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildCalendarTab(),
                _tasksTab(),
                _goalsTab(),
                _trophiesTab(),
              ],
            ),
    );
  }
 
  Widget _tasksTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _addTask,
              icon: const Icon(Icons.add),
              label: const Text('Add task'),
            ),
          ),
          ..._tasks.map((t) => CheckboxListTile(
                value: t.completed,
                title: Text(t.title),
                subtitle: Text(DateFormat.yMMMd().format(t.dueDate)),
                onChanged: (v) async {
                  await ref.read(apiServiceProvider).patchCalendarTask(t.id, {'completed': v ?? false});
                  await _loadSideData();
                  await ref.read(calendarProvider.notifier).refreshSchedule();
                },
              )),
        ],
      );
 
  Widget _goalsTab() => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _addGoal,
              icon: const Icon(Icons.add),
              label: const Text('Add goal'),
            ),
          ),
          ..._goals.map((g) {
            final progress = g.trackingMode == 'streak'
                ? g.currentStreak / g.targetDays
                : g.progressFraction;
            return Card(
              child: ListTile(
                title: Text(g.title),
                subtitle: Text('${g.checkInCount}/${g.targetDays} days • ${g.status}'),
                trailing: CircularProgressIndicator(value: progress.clamp(0, 1)),
                onTap: g.status == 'active' ? () => _checkInGoal(g) : null,
              ),
            );
          }),
        ],
      );
 
  Widget _trophiesTab() => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.2,
        ),
        itemCount: _achievements.length,
        itemBuilder: (ctx, i) {
          final a = _achievements[i];
          return Opacity(
            opacity: a.unlocked ? 1 : 0.35,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emoji_events, size: 36, color: a.unlocked ? Colors.amber : Colors.grey),
                    Text(a.title, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
 
class _CalendarSearchDelegate extends SearchDelegate<String?> {
  _CalendarSearchDelegate(this.initial);
  final String initial;
 
  @override
  String get searchFieldLabel => 'Search events...';
 
  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];
 
  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
 
  @override
  Widget buildResults(BuildContext context) {
    close(context, query);
    return const SizedBox.shrink();
  }
 
  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) query = initial;
    return const SizedBox.shrink();
  }
}
 