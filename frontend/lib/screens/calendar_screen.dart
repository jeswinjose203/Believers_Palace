import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
 
import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../core/calendar_time.dart';
import '../models/calendar_models.dart';
import '../providers/calendar_provider.dart';
import '../services/api_service.dart';
import '../services/calendar_reminder_sync.dart';
 
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
  List<PersonalCalendarEvent> _events = [];
  List<ScheduleItem> _upcomingEvents = [];
  bool _upcomingExpanded = false;
 
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
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
    await _loadEvents();
  }

  void _clearLocalSideData() {
    setState(() {
      _tasks = [];
      _goals = [];
      _achievements = [];
      _events = [];
      _upcomingEvents = [];
      _search = '';
    });
  }

  Future<void> _loadEvents() async {
    final api = ref.read(apiServiceProvider);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 8));
    final schedule = await api.getCalendarSchedule(from, to);
    final listed = await api.listCalendarEvents(limit: 200, order: 'asc');
    final upcoming = _upcomingEventsFromSchedule(schedule);
    if (!mounted) return;
    setState(() {
      _events = listed.data;
      _upcomingEvents = upcoming;
    });
  }

  List<ScheduleItem> _upcomingEventsFromSchedule(List<ScheduleItem> all) {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 7));
    bool upcomingKind(String kind) =>
        kind == 'personal_event' || kind == 'church_event';
    return all
        .where((i) {
          if (!upcomingKind(i.kind)) return false;
          final t = i.startAt ?? i.date;
          return t != null &&
              t.isAfter(now.subtract(const Duration(hours: 1))) &&
              t.isBefore(end);
        })
        .toList()
      ..sort((a, b) {
        final at = a.startAt ?? a.date ?? DateTime(0);
        final bt = b.startAt ?? b.date ?? DateTime(0);
        return at.compareTo(bt);
      });
  }
 
  Future<void> _syncNotifications() async {
    if (!mounted) return;
    await syncCalendarReminders(ref);
  }
 
  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
 
  List<ScheduleItem> _itemsForDay(DateTime day) {
    final ui = ref.read(calendarProvider);
    bool same(DateTime? d) => CalendarTime.onCalendarDay(d, day);
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
 
  Future<DateTime?> _pickDateTime(BuildContext ctx, DateTime initial, String label) async {
    final date = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'Select $label date',
    );
    if (date == null || !ctx.mounted) return null;
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Select $label time',
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
 
  Future<void> _addEvent() async {
    final title = TextEditingController();
    final desc = TextEditingController();
    var category = 'personal';
    var start = DateTime.now();
    var end = start.add(const Duration(hours: 1));
    final reminders = <int>{15};
    final fmt = DateFormat.yMMMd(context.dateLocale).add_jm();
 
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('New event')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: InputDecoration(labelText: ctx.tr('Title'))),
                TextField(controller: desc, decoration: InputDecoration(labelText: ctx.tr('Description'))),
                DropdownButtonFormField<String>(
                  value: category,
                  items: [
                    DropdownMenuItem(value: 'personal', child: Text(ctx.tr('Personal'))),
                    DropdownMenuItem(value: 'work', child: Text(ctx.tr('Work'))),
                    DropdownMenuItem(value: 'family', child: Text(ctx.tr('Family'))),
                    DropdownMenuItem(value: 'meetings', child: Text(ctx.tr('Meetings'))),
                  ],
                  onChanged: (v) => setSt(() => category = v ?? 'personal'),
                  decoration: InputDecoration(labelText: ctx.tr('Category')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ctx.tr('Starts')),
                  subtitle: Text(fmt.format(start)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await _pickDateTime(ctx, start, 'start');
                    if (picked != null) {
                      setSt(() {
                        start = picked;
                        if (!end.isAfter(start)) {
                          end = start.add(const Duration(hours: 1));
                        }
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ctx.tr('Ends')),
                  subtitle: Text(fmt.format(end)),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final picked = await _pickDateTime(ctx, end, 'end');
                    if (picked != null) {
                      setSt(() => end = picked);
                    }
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(ctx.tr('Reminders (minutes before start — e.g. 5 = 5 min earlier)')),
                ),
                Wrap(
                  spacing: 8,
                  children: [5, 15, 30, 60, 1440].map((m) {
                    final selected = reminders.contains(m);
                    return FilterChip(
                      label: Text(m >= 60 ? '${m ~/ 60}h' : '$m'),
                      selected: selected,
                      onSelected: (v) => setSt(() {
                        if (v) {
                          reminders.add(m);
                        } else {
                          reminders.remove(m);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    if (!end.isAfter(start)) {
      if (mounted) _toast(context.tr('End must be after start'));
      return;
    }
    try {
      await ref.read(apiServiceProvider).createCalendarEvent({
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'category': category,
        'startAt': CalendarTime.localDateTimeToUtcIso(start),
        'endAt': CalendarTime.localDateTimeToUtcIso(end),
        'recurrence': 'none',
        'reminderMinutes': reminders.toList()..sort(),
      });
      await ref.read(calendarProvider.notifier).refreshSchedule();
      await _loadEvents();
      await _syncNotifications();
      if (mounted) _toast(context.tr('Event created'));
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _editTask(CalendarTask t) async {
    final title = TextEditingController(text: t.title);
    var due = t.dueDate.toLocal();
    final fmt = DateFormat.yMMMd(context.dateLocale).add_jm();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('Edit task')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: ctx.tr('Title'))),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(ctx.tr('Due')),
                subtitle: Text(fmt.format(due)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final picked = await _pickDateTime(ctx, due, 'due');
                  if (picked != null) setSt(() => due = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await ref.read(apiServiceProvider).patchCalendarTask(t.id, {
        'title': title.text.trim(),
        'dueDate': CalendarTime.localDateTimeToUtcIso(due),
      });
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      await _syncNotifications();
      if (mounted) _toast(context.tr('Task updated'));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _addTask() async {
    final title = TextEditingController();
    var due = DateTime.now().add(const Duration(hours: 1));
    final fmt = DateFormat.yMMMd(context.dateLocale).add_jm();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('New task')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: ctx.tr('Title'))),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(ctx.tr('Due')),
                subtitle: Text(fmt.format(due)),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final picked = await _pickDateTime(ctx, due, 'due');
                  if (picked != null) setSt(() => due = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await ref.read(apiServiceProvider).createCalendarTask({
        'title': title.text.trim(),
        'dueDate': CalendarTime.localDateTimeToUtcIso(due),
      });
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      await _syncNotifications();
      if (mounted) _toast(context.tr('Task added'));
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _addGoal() async {
    final title = TextEditingController();
    final target = TextEditingController(text: '7');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('New goal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: ctx.tr('Title'))),
              TextField(controller: target, decoration: InputDecoration(labelText: ctx.tr('Target days')), keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      await ref.read(apiServiceProvider).createCalendarGoal({
        'title': title.text.trim(),
        'targetDays': int.tryParse(target.text) ?? 7,
        'startDate': CalendarTime.localDateTimeToUtcIso(start),
      });
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      if (mounted) _toast(context.tr('Goal created'));
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _editGoal(CalendarGoal g) async {
    final title = TextEditingController(text: g.title);
    final target = TextEditingController(text: '${g.targetDays}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('Edit goal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: ctx.tr('Title'))),
              TextField(
                controller: target,
                decoration: InputDecoration(labelText: ctx.tr('Target days')),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await ref.read(apiServiceProvider).updateCalendarGoal(g.id, {
        'title': title.text.trim(),
        'targetDays': int.tryParse(target.text) ?? g.targetDays,
      });
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      if (mounted) _toast(context.tr('Goal updated'));
    } catch (e) {
      _toast('$e');
    }
  }
 
  Future<void> _deleteGoal(CalendarGoal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Delete goal?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteCalendarGoal(g.id);
    await _loadSideData();
    await ref.read(calendarProvider.notifier).refreshSchedule();
  }
 
  Future<void> _checkInGoal(CalendarGoal g, {DateTime? forDay}) async {
    await _checkInGoalById(g.id, forDay: forDay);
  }

  Future<void> _checkInGoalById(String goalId, {DateTime? forDay}) async {
    final day = forDay ?? DateTime.now();
    final ymd = CalendarTime.localDateToYmd(day);
    try {
      final resp = await ref.read(apiServiceProvider).checkInGoal(goalId, ymd);
      await _loadSideData();
      await ref.read(calendarProvider.notifier).refreshSchedule();
      if (resp.newAchievements.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.tr('Achievement unlocked!')),
            content: Text(resp.newAchievements.map((a) => a.title).join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('Nice')))],
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
              Expanded(
                child: SegmentedButton<CalendarViewMode>(
                  segments: [
                    ButtonSegment(value: CalendarViewMode.month, label: Text(context.tr('Month'))),
                    ButtonSegment(value: CalendarViewMode.week, label: Text(context.tr('Week'))),
                    ButtonSegment(value: CalendarViewMode.day, label: Text(context.tr('Day'))),
                  ],
                  selected: {ui.viewMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) async {
                    await ref.read(calendarProvider.notifier).setViewMode(s.first);
                  },
                ),
              ),
              IconButton(icon: const Icon(Icons.add), onPressed: _addEvent),
            ],
          ),
        ),
        if (ui.viewMode == CalendarViewMode.month)
          TableCalendar(
            locale: context.dateLocale,
            availableCalendarFormats: {
              CalendarFormat.month: context.tr('Month'),
            },
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: ui.focusedDay,
            selectedDayPredicate: (d) => isSameDay(d, ui.selectedDay),
            startingDayOfWeek: weekStart,
            eventLoader: (day) => _itemsForDay(day),
            onDaySelected: (sel, focus) {
              ref.read(calendarProvider.notifier).selectDay(sel);
              _showDaySheet(sel);
            },
            calendarStyle: const CalendarStyle(markersMaxCount: 3),
          ),
        if (ui.viewMode == CalendarViewMode.week) _buildWeekStrip(ui),
        if (ui.viewMode == CalendarViewMode.day) _buildDayNavigator(ui),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            child: _buildScheduleList(ui),
          ),
        ),
      ],
    );
  }
 
  Widget _buildWeekStrip(CalendarUiState ui) {
    final sundayStart = ui.preferences?.weekStartsOn == 'sunday';
    final ws = CalendarNotifier.weekStart(ui.selectedDay, sundayStart: sundayStart);
  final fmt = DateFormat.E(context.dateLocale);
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: 7,
        itemBuilder: (ctx, i) {
          final day = ws.add(Duration(days: i));
          final selected = isSameDay(day, ui.selectedDay);
          final count = _itemsForDay(day).length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fmt.format(day)),
                  Text('${day.day}', style: const TextStyle(fontSize: 16)),
                  if (count > 0) Text('$count', style: const TextStyle(fontSize: 11)),
                ],
              ),
              selected: selected,
              onSelected: (_) {
                ref.read(calendarProvider.notifier).selectDay(day);
              },
            ),
          );
        },
      ),
    );
  }
 
  Widget _buildDayNavigator(CalendarUiState ui) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              final d = ui.selectedDay.subtract(const Duration(days: 1));
              ref.read(calendarProvider.notifier).selectDay(d);
            },
          ),
          Expanded(
            child: Text(
              DateFormat.yMMMEd(context.dateLocale).format(ui.selectedDay),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              final d = ui.selectedDay.add(const Duration(days: 1));
              ref.read(calendarProvider.notifier).selectDay(d);
            },
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () => ref.read(calendarProvider.notifier).selectDay(DateTime.now()),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList(CalendarUiState ui) {
    switch (ui.viewMode) {
      case CalendarViewMode.week:
        return _weekList(ui);
      case CalendarViewMode.day:
        return _dayList(ui);
      case CalendarViewMode.month:
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(DateFormat.yMMMd(context.dateLocale).format(ui.selectedDay),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_itemsForDay(ui.selectedDay).isEmpty)
              Text(context.tr('Nothing on this day'))
            else
              ..._itemsForDay(ui.selectedDay).map(_scheduleTile),
          ],
        );
    }
  }
 
  Widget _weekList(CalendarUiState ui) {
    final sundayStart = ui.preferences?.weekStartsOn == 'sunday';
    final ws = CalendarNotifier.weekStart(ui.selectedDay, sundayStart: sundayStart);
    final children = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final day = ws.add(Duration(days: i));
      final items = _itemsForDay(day);
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(DateFormat.yMMMEd(context.dateLocale).format(day),
              style: Theme.of(context).textTheme.titleSmall),
        ),
      );
      if (items.isEmpty) {
        children.add(Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(context.tr('No items')),
        ));
      } else {
        children.addAll(items.map(_scheduleTile));
      }
      children.add(const Divider(height: 16));
    }
    return ListView(children: children);
  }
 
  Widget _dayList(CalendarUiState ui) {
    final items = _itemsForDay(ui.selectedDay);
    final timed = items.where((i) => i.startAt != null).toList()
      ..sort((a, b) => a.startAt!.compareTo(b.startAt!));
    final untimed = items.where((i) => i.startAt == null).toList();
    final fmt = DateFormat.jm(context.dateLocale);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (timed.isNotEmpty)
          Text(context.tr('Timed'), style: Theme.of(context).textTheme.titleMedium),
        ...timed.map((i) {
          final t = i.startAt!;
          return ListTile(
            leading: Text(fmt.format(t)),
            title: Text(i.title ?? context.tr('Untitled')),
            subtitle: Text(i.kind),
          );
        }),
        if (untimed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(context.tr('All day / other'), style: Theme.of(context).textTheme.titleMedium),
          ...untimed.map(_scheduleTile),
        ],
        if (items.isEmpty) Text(context.tr('Nothing on this day')),
      ],
    );
  }
 
  Widget _scheduleTile(ScheduleItem i) {
    Color? accent;
    if (i.color != null) {
      accent = _parseColor(i.color!);
    }
    final subtitle = switch (i.kind) {
      'booking' => context.tr('Hall booking • {0}', [context.tr(i.status ?? '')]),
      'church_event' => context.tr('Church event'),
      'holiday' => context.tr('Public holiday'),
      'task' => context.tr('Task'),
      'goal_checkin_due' => context.tr(
          i.checkedInOnDay == true ? 'Checked in' : 'Check in for this day',
        ),
      _ => i.category ?? context.tr('Personal'),
    };
    final selected = ref.read(calendarProvider).selectedDay;
  Widget? trailing;
    if (i.kind == 'goal_checkin_due' &&
        i.goalId != null &&
        i.checkedInOnDay != true) {
      final day = i.date ?? selected;
      trailing = TextButton(
        onPressed: () => _checkInGoalById(i.goalId!, forDay: day),
        child: Text(context.tr('Check in')),
      );
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: accent ?? Theme.of(context).colorScheme.primaryContainer,
        child: Icon(_iconFor(i.kind), size: 18),
      ),
      title: Text(i.title ?? context.tr('Untitled')),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: switch (i.kind) {
        'personal_event' when i.id != null => () => _managePersonalEvent(i.id!),
        'goal_checkin_due' when i.goalId != null && i.checkedInOnDay != true =>
          () => _checkInGoalById(i.goalId!, forDay: i.date ?? selected),
        _ => null,
      },
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
 
  Future<void> _managePersonalEvent(String id) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(ctx.tr('Edit event')),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(ctx.tr('Delete event')),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      await _deletePersonalEvent(id);
    } else if (action == 'edit') {
      await _editPersonalEvent(id);
    }
  }

  Future<void> _editPersonalEvent(String id) async {
    final api = ref.read(apiServiceProvider);
    PersonalCalendarEvent e;
    try {
      e = await api.getCalendarEvent(id);
    } catch (err) {
      _toast('$err');
      return;
    }
    if (!mounted) return;
    final title = TextEditingController(text: e.title);
    final desc = TextEditingController(text: e.description ?? '');
    var category = e.category;
    var start = e.startAt.toLocal();
    var end = e.endAt.toLocal();
    final reminders = e.reminderMinutes.toSet();
    final fmt = DateFormat.yMMMd(context.dateLocale).add_jm();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(ctx.tr('Edit event')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: InputDecoration(labelText: ctx.tr('Title'))),
                TextField(controller: desc, decoration: InputDecoration(labelText: ctx.tr('Description'))),
                DropdownButtonFormField<String>(
                  value: category,
                  items: [
                    DropdownMenuItem(value: 'personal', child: Text(ctx.tr('Personal'))),
                    DropdownMenuItem(value: 'work', child: Text(ctx.tr('Work'))),
                    DropdownMenuItem(value: 'family', child: Text(ctx.tr('Family'))),
                    DropdownMenuItem(value: 'meetings', child: Text(ctx.tr('Meetings'))),
                  ],
                  onChanged: (v) => setSt(() => category = v ?? category),
                  decoration: InputDecoration(labelText: ctx.tr('Category')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ctx.tr('Starts')),
                  subtitle: Text(fmt.format(start)),
                  onTap: () async {
                    final picked = await _pickDateTime(ctx, start, 'start');
                    if (picked != null) setSt(() => start = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ctx.tr('Ends')),
                  subtitle: Text(fmt.format(end)),
                  onTap: () async {
                    final picked = await _pickDateTime(ctx, end, 'end');
                    if (picked != null) setSt(() => end = picked);
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(ctx.tr('Reminders (minutes before start — e.g. 5 = 5 min earlier)')),
                ),
                Wrap(
                  spacing: 8,
                  children: [5, 15, 30, 60, 1440].map((m) {
                    final selected = reminders.contains(m);
                    return FilterChip(
                      label: Text(m >= 60 ? '${m ~/ 60}h' : '$m'),
                      selected: selected,
                      onSelected: (v) => setSt(() {
                        if (v) {
                          reminders.add(m);
                        } else {
                          reminders.remove(m);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    if (!end.isAfter(start)) {
      if (mounted) _toast(context.tr('End must be after start'));
      return;
    }
    try {
      await api.updateCalendarEvent(id, {
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'category': category,
        'startAt': CalendarTime.localDateTimeToUtcIso(start),
        'endAt': CalendarTime.localDateTimeToUtcIso(end),
        'recurrence': e.recurrence,
        'reminderMinutes': reminders.toList()..sort(),
      });
      await ref.read(calendarProvider.notifier).refreshSchedule();
      await _loadEvents();
      await _syncNotifications();
      if (mounted) _toast(context.tr('Event updated'));
    } catch (err) {
      _toast('$err');
    }
  }

  Future<void> _deletePersonalEvent(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Delete event?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteCalendarEvent(id);
    await ref.read(calendarProvider.notifier).refreshSchedule();
    await _loadEvents();
    await _syncNotifications();
  }
 
  void _showDaySheet(DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(DateFormat.yMMMEd(context.dateLocale).format(day), style: Theme.of(context).textTheme.titleLarge),
            ..._itemsForDay(day).map(_scheduleTile),
          ],
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider.select((s) => s.user?.id), (prev, next) {
      if (prev == next) return;
      _clearLocalSideData();
      if (next != null) {
        Future.microtask(_loadAll);
      }
    });
    final ui = ref.watch(calendarProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('My Calendar')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr('Calendar')),
            Tab(text: context.tr('Events')),
            Tab(text: context.tr('Tasks')),
            Tab(text: context.tr('Goals')),
            Tab(text: context.tr('Trophies')),
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
                _eventsTab(),
                _tasksTab(),
                _goalsTab(),
                _trophiesTab(),
              ],
            ),
    );
  }
 
  Widget _eventsTab() {
    final dateFmt = DateFormat.yMMMd(context.dateLocale).add_jm();
    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _addEvent,
              icon: const Icon(Icons.add),
              label: Text(context.tr('New event')),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                ListTile(
                  title: Text(context.tr('Upcoming (7 days)'), style: Theme.of(context).textTheme.titleMedium),
                  trailing: Icon(_upcomingExpanded ? Icons.expand_less : Icons.expand_more),
                  onTap: () => setState(() => _upcomingExpanded = !_upcomingExpanded),
                ),
                if (_upcomingExpanded) ...[
                  const Divider(height: 1),
                  if (_upcomingEvents.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        context.tr('No upcoming events in the next 7 days (set My church to see church events)'),
                      ),
                    )
                  else
                    ..._upcomingEvents.map((i) {
                      final when = (i.startAt ?? i.date)?.toLocal();
                      final isPersonal = i.kind == 'personal_event';
                      final kindLabel = isPersonal ? 'Your event' : 'Church event';
                      return ListTile(
                        leading: Icon(isPersonal ? Icons.event : Icons.church),
                        title: Text(i.title ?? context.tr('Untitled')),
                        subtitle: Text(
                          when != null ? '$kindLabel • ${dateFmt.format(when)}' : kindLabel,
                        ),
                        onTap: isPersonal && i.id != null
                            ? () => _managePersonalEvent(i.id!)
                            : null,
                      );
                    }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(context.tr('Your events'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_events.isEmpty)
            Text(context.tr('No events yet. Tap New event to create one.'))
          else
            ..._events.map((e) {
              final start = e.startAt.toLocal();
              final end = e.endAt.toLocal();
              final range = e.allDay
                  ? DateFormat.yMMMd(context.dateLocale).format(start)
                  : '${dateFmt.format(start)} – ${DateFormat.jm(context.dateLocale).format(end)}';
              return Card(
                child: ListTile(
                  title: Text(e.title),
                  subtitle: Text('$range • ${e.category}'),
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(context.tr('Edit'))),
                      PopupMenuItem(value: 'delete', child: Text(context.tr('Delete'))),
                    ],
                    onSelected: (v) async {
                      switch (v) {
                        case 'edit':
                          await _editPersonalEvent(e.id);
                        case 'delete':
                          await _deletePersonalEvent(e.id);
                      }
                    },
                  ),
                  onTap: () => _editPersonalEvent(e.id),
                ),
              );
            }),
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
              label: Text(context.tr('Add task')),
            ),
          ),
          ..._tasks.map((t) {
            final dueLocal = t.dueDate.toLocal();
            final subtitle = DateFormat.yMMMd(context.dateLocale).add_jm().format(dueLocal);
            return Card(
              child: Row(
                children: [
                  Checkbox(
                    value: t.completed,
                    onChanged: (v) async {
                      await ref.read(apiServiceProvider).patchCalendarTask(t.id, {'completed': v ?? false});
                      await _loadSideData();
                      await ref.read(calendarProvider.notifier).refreshSchedule();
                      await _syncNotifications();
                    },
                  ),
                  Expanded(
                    child: ListTile(
                      title: Text(t.title),
                      subtitle: Text(subtitle),
                      onTap: () => _editTask(t),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
 
  Widget _goalsTab() {
    final selectedDay = ref.watch(calendarProvider).selectedDay;
    return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _addGoal,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add goal')),
            ),
          ),
          ..._goals.map((g) {
            final progress = g.progressFraction;
            final streakLabel = g.currentStreak > 0
                ? '${g.currentStreak} day streak'
                : null;
            return Card(
              child: ListTile(
                title: Row(
                  children: [
                    Expanded(child: Text(g.title)),
                    if (streakLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${g.currentStreak}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  streakLabel != null
                      ? context.tr('{0}/{1} days • {2} • {3}', [g.checkInCount, g.targetDays, streakLabel, g.status])
                      : context.tr('{0}/{1} days • {2}', [g.checkInCount, g.targetDays, g.status]),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(value: progress.clamp(0, 1)),
                    ),
                    PopupMenuButton<String>(
                      itemBuilder: (_) => [
                        if (g.status == 'active')
                          PopupMenuItem(
                            value: 'checkin',
                            child: Text(
                              CalendarTime.sameCalendarDay(selectedDay, DateTime.now())
                                  ? context.tr('Check in today')
                                  : context.tr('Check in for {0}', [DateFormat.yMMMd(context.dateLocale).format(selectedDay)]),
                            ),
                          ),
                        PopupMenuItem(value: 'edit', child: Text(context.tr('Edit'))),
                        PopupMenuItem(value: 'delete', child: Text(context.tr('Delete'))),
                      ],
                      onSelected: (v) async {
                        switch (v) {
                          case 'checkin':
                            await _checkInGoal(g, forDay: selectedDay);
                          case 'edit':
                            await _editGoal(g);
                          case 'delete':
                            await _deleteGoal(g);
                        }
                      },
                    ),
                  ],
                ),
                onTap: g.status == 'active' ? () => _checkInGoal(g, forDay: selectedDay) : null,
              ),
            );
          }),
        ],
      );
  }

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
