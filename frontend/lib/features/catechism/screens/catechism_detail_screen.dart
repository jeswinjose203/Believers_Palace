import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import '../widgets/status_chip.dart';
import 'enroll_form_screen.dart';
import 'manage_class_form_screen.dart';
import 'manage_enrollments_screen.dart';
import 'session_form_screen.dart';

class CatechismDetailScreen extends ConsumerStatefulWidget {
  final String classId;
  final bool canManage;

  const CatechismDetailScreen({
    super.key,
    required this.classId,
    required this.canManage,
  });

  @override
  ConsumerState<CatechismDetailScreen> createState() =>
      _CatechismDetailScreenState();
}

class _CatechismDetailScreenState extends ConsumerState<CatechismDetailScreen> {
  Future<CatechismClass>? _classFuture;
  Future<List<CatechismSession>>? _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final api = ref.read(catechismApiProvider);
    _classFuture = api.getClass(widget.classId);
    _sessionsFuture = api
        .listSessions(widget.classId, limit: 50)
        .then((p) => p.data);
  }

  void _refresh() => setState(_reload);

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red.shade700 : null),
    );
  }

  Future<void> _enroll(CatechismClass cls) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EnrollFormScreen(catechismClass: cls),
      ),
    );
    if (ok == true) {
      _snack('Enrollment submitted');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class details'),
        actions: [
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.groups_outlined),
              tooltip: 'Manage enrollments',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ManageEnrollmentsScreen(classId: widget.classId),
                  ),
                );
                _refresh();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<CatechismClass>(
          future: _classFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _refresh, child: const Text('Retry')),
                      ],
                    ),
                  ),
                ],
              );
            }
            final cls = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (cls.image != null && cls.image!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      cls.image!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(cls.name, style: Theme.of(context).textTheme.headlineSmall),
                Text(levelLabel(cls.level)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [CatechismStatusChip(status: cls.status)],
                ),
                const SizedBox(height: 12),
                if (cls.description != null && cls.description!.isNotEmpty)
                  Text(cls.description!),
                const SizedBox(height: 8),
                Text('${df.format(cls.startDate)} – ${df.format(cls.endDate)}'),
                if (cls.location != null) Text('Location: ${cls.location}'),
                if (cls.teacherName != null && cls.teacherName!.isNotEmpty)
                  Text('Teacher: ${cls.teacherName}'),
                Text('Seats: ${cls.availableSeats} available (${cls.enrolledCount}/${cls.capacity})'),
                if (cls.schedule.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w600)),
                  for (final s in cls.schedule) Text('${s.day} at ${s.time}'),
                ],
                const SizedBox(height: 16),
                if (!widget.canManage && cls.status == 'open' && !cls.enrolled)
                  FilledButton(
                    onPressed: cls.availableSeats > 0 ? () => _enroll(cls) : null,
                    child: const Text('Enroll a student'),
                  ),
                if (widget.canManage) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ManageClassFormScreen(
                                  churchId: cls.churchId,
                                  existing: cls,
                                ),
                              ),
                            );
                            _refresh();
                          },
                          child: const Text('Edit class'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SessionFormScreen(classId: cls.id),
                              ),
                            );
                            _refresh();
                          },
                          child: const Text('Add lesson'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text('Lessons', style: Theme.of(context).textTheme.titleMedium),
                FutureBuilder<List<CatechismSession>>(
                  future: _sessionsFuture,
                  builder: (context, sessSnap) {
                    if (sessSnap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (sessSnap.hasError) {
                      final err = sessSnap.error;
                      if (err is ApiException && err.statusCode == 403) {
                        return const Text('Lessons are visible after your enrollment is approved.');
                      }
                      return Text('Could not load lessons: $err');
                    }
                    final sessions = sessSnap.data ?? [];
                    if (sessions.isEmpty) {
                      return const Text('No lessons scheduled yet.');
                    }
                    return Column(
                      children: [
                        for (final s in sessions)
                          ListTile(
                            title: Text(s.title),
                            subtitle: Text(
                              '${df.format(s.sessionDate)} · ${s.startTime} – ${s.endTime}'
                              '${s.topic != null ? '\n${s.topic}' : ''}',
                            ),
                            trailing: widget.canManage
                                ? IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => SessionFormScreen(
                                            classId: cls.id,
                                            existing: s,
                                          ),
                                        ),
                                      );
                                      _refresh();
                                    },
                                  )
                                : null,
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}