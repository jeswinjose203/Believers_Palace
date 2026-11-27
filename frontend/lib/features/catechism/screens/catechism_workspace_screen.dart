import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_locale.dart';
import '../../../core/api_client.dart';
import '../../../core/auth_provider.dart';
import '../services/catechism_api.dart';

typedef _Row = Map<String, dynamic>;
const _pageSize = 20;

String _publicationRequestId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
}

List<_Row> _rows(_Row data, String key) =>
    (data[key] as List<dynamic>).cast<_Row>();

class CatechismTeacherScreen extends ConsumerStatefulWidget {
  const CatechismTeacherScreen({super.key});

  @override
  ConsumerState<CatechismTeacherScreen> createState() =>
      _CatechismTeacherScreenState();
}

class _CatechismTeacherScreenState
    extends ConsumerState<CatechismTeacherScreen> {
  late Future<_Row> _classes;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _classes = ref.read(catechismApiProvider).teacherClasses(_page);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Catechism teacher')),
          actions: [
            IconButton(
              tooltip: context.tr('Sign out'),
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
        body: _WorkspaceData(
          future: _classes,
          retry: () => setState(_load),
          builder: (data) {
            final classes = _rows(data, 'classes');
            return ListView(
              children: [
                if (classes.isEmpty)
                  ListTile(title: Text(context.tr('No assigned classes'))),
                for (final cls in classes.take(_pageSize))
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: Text(cls['name'] as String),
                    subtitle: Text(
                      "${cls['church']} · ${cls['substitute'] == true ? 'Substitute' : 'Teacher'}",
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CatechismWorkspaceScreen(
                          classId: cls['id'] as String,
                          title: cls['name'] as String,
                        ),
                      ),
                    ),
                  ),
                _PageControls(
                  page: _page,
                  hasMore: classes.length > _pageSize,
                  onChanged: (page) => setState(() {
                    _page = page;
                    _load();
                  }),
                ),
              ],
            );
          },
        ),
      );
}

class CatechismWorkspaceScreen extends ConsumerStatefulWidget {
  const CatechismWorkspaceScreen({
    super.key,
    required this.classId,
    this.title = 'Class workspace',
  });

  final String classId;
  final String title;

  @override
  ConsumerState<CatechismWorkspaceScreen> createState() =>
      _CatechismWorkspaceScreenState();
}

class _CatechismWorkspaceScreenState
    extends ConsumerState<CatechismWorkspaceScreen> {
  late Future<_Row> _workspace;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _workspace =
        ref.read(catechismApiProvider).workspace(widget.classId, _page);
  }

  Future<void> _edit(
    String action,
    String title,
    List<(String, String)> fields, {
    _Row? student,
    _Row initial = const {},
  }) async {
    final api = ref.read(catechismApiProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorkspaceEditor(
        action: action,
        title: title,
        fields: fields,
        initial: initial,
        save: (body) => api.saveWorkspace(widget.classId, action, {
          ...body,
          if (student != null) 'enrollmentId': student['id'],
        }),
      ),
    );
    if (saved == true && mounted) {
      setState(_load);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('Saved'))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: context.tr('Refresh'),
              onPressed: () => setState(_load),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _WorkspaceData(
          future: _workspace,
          retry: () => setState(_load),
          builder: _buildWorkspace,
        ),
      );

  Widget _buildWorkspace(_Row data) {
    final canRegister = data['canRegister'] == true;
    final canTeach = data['canTeach'] == true;
    final students = _rows(data, 'students');
    final teachers = _rows(data, 'teachers');
    final publications = _rows(data, 'publications');
    final syllabus = data['syllabus'] as _Row?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canRegister) ...[
              OutlinedButton(
                onPressed: () => _edit('students', 'Register student', const [
                  ('studentName', 'Student name'),
                  ('dateOfBirth', 'Date of birth'),
                  ('email', 'Guardian account email'),
                  ('notes', 'Notes (optional)'),
                ]),
                child: Text(context.tr('Register student')),
              ),
              OutlinedButton(
                onPressed: () => _edit('teachers', 'Register teacher', const [
                  ('email', 'Teacher email'),
                  ('name', 'Name for a new account'),
                  ('password', 'Initial password for a new account'),
                ]),
                child: Text(context.tr('Register teacher')),
              ),
            ],
            if (canTeach) ...[
              OutlinedButton(
                onPressed: () => _edit(
                  'syllabus',
                  'Publish syllabus',
                  const [('title', 'Title'), ('body', 'Syllabus')],
                  initial: syllabus ?? const {},
                ),
                child: Text(
                    syllabus == null ? context.tr('Publish syllabus') : context.tr('Update syllabus')),
              ),
              OutlinedButton(
                onPressed: () => _edit(
                  'announcement',
                  'Post announcement',
                  const [('title', 'Title'), ('body', 'Announcement')],
                ),
                child: Text(context.tr('Post announcement')),
              ),
            ],
          ],
        ),
        if (canRegister) ...[
          ListTile(title: Text(context.tr('Teachers'))),
          if (teachers.isEmpty)
            ListTile(subtitle: Text(context.tr('No teachers assigned'))),
          for (final teacher in teachers.take(_pageSize))
            ListTile(
              title: Text(teacher['name'] as String),
              subtitle: Text(teacher['email'] as String),
              trailing: Text(
                  teacher['substitute'] == true ? context.tr('Substitute') : context.tr('Teacher')),
            ),
        ],
        if (canRegister || canTeach || students.isNotEmpty) ...[
          ListTile(title: Text(context.tr('Students'))),
          if (students.isEmpty)
            ListTile(subtitle: Text(context.tr('No registered students'))),
          for (final student in students.take(_pageSize))
            ExpansionTile(
              title: Text(student['name'] as String),
              children: [
                if (canTeach)
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _edit(
                          'attendance',
                          'Mark attendance for ${student['name']}',
                          const [('date', 'Lesson date')],
                          student: student,
                        ),
                        child: Text(context.tr('Mark attendance')),
                      ),
                      OutlinedButton(
                        onPressed: () => _edit(
                          'marks',
                          'Publish marks for ${student['name']}',
                          const [
                            ('assessment', 'Assessment'),
                            ('score', 'Score'),
                            ('maximum', 'Maximum score'),
                          ],
                          student: student,
                        ),
                        child: Text(context.tr('Publish marks')),
                      ),
                    ],
                  ),
                if (student['canViewHistory'] == true)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _StudentHistoryScreen(
                          classId: widget.classId,
                          studentId: student['id'] as String,
                          name: student['name'] as String,
                        ),
                      ),
                    ),
                    child: Text(context.tr('View attendance and marks')),
                  ),
              ],
            ),
        ],
        ListTile(title: Text(context.tr('Syllabus and announcements'))),
        if (publications.isEmpty && syllabus == null)
          ListTile(subtitle: Text(context.tr('No class updates available'))),
        for (final publication in [
          if (syllabus != null) syllabus,
          ...publications.take(_pageSize),
        ])
          Card(
            child: ListTile(
              title: Text(publication['title'] as String),
              leading: Text(
                publication['kind'] == 'syllabus' ? context.tr('Syllabus') : context.tr('Announcement'),
              ),
              subtitle: Text(publication['body'] as String),
            ),
          ),
        _PageControls(
          page: _page,
          hasMore: [students, teachers, publications]
              .any((items) => items.length > _pageSize),
          onChanged: (page) => setState(() {
            _page = page;
            _load();
          }),
        ),
      ],
    );
  }
}

class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.page,
    required this.hasMore,
    required this.onChanged,
  });

  final int page;
  final bool hasMore;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (page == 1 && !hasMore) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: page > 1 ? () => onChanged(page - 1) : null,
          child: Text(context.tr('Previous')),
        ),
        Text(context.tr('Page {0}', [page])),
        TextButton(
          onPressed: hasMore ? () => onChanged(page + 1) : null,
          child: Text(context.tr('Next')),
        ),
      ],
    );
  }
}

class _StudentHistoryScreen extends ConsumerStatefulWidget {
  const _StudentHistoryScreen({
    required this.classId,
    required this.studentId,
    required this.name,
  });

  final String classId;
  final String studentId;
  final String name;

  @override
  ConsumerState<_StudentHistoryScreen> createState() => _StudentHistoryState();
}

class _StudentHistoryState extends ConsumerState<_StudentHistoryScreen> {
  late Future<_Row> _history;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _history = ref.read(catechismApiProvider).studentHistory(
          widget.classId,
          widget.studentId,
          _page,
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: _WorkspaceData(
          future: _history,
          retry: () => setState(_load),
          builder: (data) {
            final marks = _rows(data, 'marks');
            final attendance = _rows(data, 'attendance');
            return ListView(children: [
              ListTile(title: Text(context.tr('Published marks'))),
              if (marks.isEmpty)
                ListTile(subtitle: Text(context.tr('No marks on this page'))),
              for (final mark in marks.take(_pageSize))
                ListTile(
                  title: Text(mark['assessment'] as String),
                  trailing: Text("${mark['score']} / ${mark['maximum']}"),
                ),
              ListTile(title: Text(context.tr('Attendance'))),
              if (attendance.isEmpty)
                ListTile(subtitle: Text(context.tr('No attendance on this page'))),
              for (final entry in attendance.take(_pageSize))
                ListTile(
                  title: Text(entry['lesson_date'] as String),
                  trailing: Text(context.tr(entry['status'] as String)),
                ),
              _PageControls(
                page: _page,
                hasMore:
                    marks.length > _pageSize || attendance.length > _pageSize,
                onChanged: (page) => setState(() {
                  _page = page;
                  _load();
                }),
              ),
            ]);
          },
        ),
      );
}

class _WorkspaceData extends StatelessWidget {
  const _WorkspaceData({
    required this.future,
    required this.retry,
    required this.builder,
  });

  final Future<_Row> future;
  final VoidCallback retry;
  final Widget Function(_Row) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<_Row>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_errorMessage(snapshot.error)),
                  TextButton(onPressed: retry, child: Text(context.tr('Retry'))),
                ],
              ),
            );
          }
          return builder(snapshot.requireData);
        },
      );
}

String _errorMessage(Object? error) =>
    error is ApiException ? error.message : 'Could not complete the request';

class _WorkspaceEditor extends StatefulWidget {
  const _WorkspaceEditor({
    required this.action,
    required this.title,
    required this.fields,
    required this.initial,
    required this.save,
  });

  final String action;
  final String title;
  final List<(String, String)> fields;
  final _Row initial;
  final Future<void> Function(_Row) save;

  @override
  State<_WorkspaceEditor> createState() => _WorkspaceEditorState();
}

class _WorkspaceEditorState extends State<_WorkspaceEditor> {
  late final _controllers = {
    for (final (key, _) in widget.fields)
      key: TextEditingController(text: widget.initial[key]?.toString()),
  };

  late final String _requestId = _publicationRequestId();
  String _status = 'present';
  bool _substitute = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(String key) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final birthday = key == 'dateOfBirth';
    final date = await showDatePicker(
      context: context,
      initialDate: birthday ? DateTime(today.year - 10) : today,
      firstDate: DateTime(1900),
      lastDate: birthday ? today : DateTime(today.year + 1, 12, 31),
    );
    if (mounted && date != null) {
      _controllers[key]!.text = DateFormat('yyyy-MM-dd').format(date);
    }
  }

  Future<void> _save() async {
    final body = <String, dynamic>{
      for (final entry in _controllers.entries)
        entry.key: entry.key == 'password'
            ? entry.value.text
            : entry.value.text.trim(),
    };
    switch (widget.action) {
      case 'students':
        final birthDate = body['dateOfBirth'] as String;
        if (birthDate.isEmpty) {
          setState(() => _error = 'Select a date of birth');
          return;
        }
        body['dateOfBirth'] = '${birthDate}T00:00:00Z';
      case 'teachers':
        body['substitute'] = _substitute;
      case 'attendance':
        body['status'] = _status;
      case 'announcement':
        body['requestId'] = _requestId;
      case 'marks':
        body['score'] = int.tryParse(body['score'] as String);
        body['maximum'] = int.tryParse(body['maximum'] as String) ?? 0;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(widget.title),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, label) in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _controllers[key],
                    decoration: InputDecoration(labelText: label),
                    enabled: !_saving,
                    obscureText: key == 'password',
                    maxLines: key == 'body' ? 5 : 1,
                    keyboardType: switch (key) {
                      'score' || 'maximum' => TextInputType.number,
                      'email' => TextInputType.emailAddress,
                      _ => TextInputType.text,
                    },
                    readOnly: key == 'date' || key == 'dateOfBirth',
                    onTap: key == 'date' || key == 'dateOfBirth'
                        ? () => _pickDate(key)
                        : null,
                  ),
                ),
              if (widget.action == 'teachers') ...[
                Text(context.tr('For an existing account, enter the email only.')),
                SwitchListTile(
                  title: Text(context.tr('Substitute teacher')),
                  value: _substitute,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _substitute = value),
                ),
              ],
              if (widget.action == 'attendance')
                DropdownButton<String>(
                  value: _status,
                  items: [
                    DropdownMenuItem(value: 'present', child: Text(context.tr('Present'))),
                    DropdownMenuItem(value: 'absent', child: Text(context.tr('Absent'))),
                    DropdownMenuItem(value: 'excused', child: Text(context.tr('Excused'))),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
              if (_error != null)
                Text(context.tr(_error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? context.tr('Saving…') : context.tr('Save')),
            ),
          ],
        ),
      );
}
