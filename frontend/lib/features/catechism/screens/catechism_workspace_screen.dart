import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_locale.dart';
import '../../../core/api_client.dart';
import '../services/catechism_api.dart';

typedef _Row = Map<String, dynamic>;
const _pageSize = 20;

String _publicationRequestId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
}

List<_Row> _rows(_Row data, String key) =>
    ((data[key] as List<dynamic>?) ?? const <dynamic>[]).cast<_Row>();

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

  Future<void> _leaveClass(_Row cls) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Leave this class?')),
        content: Text(cls['name'] as String? ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Leave class')),
          ),
        ],
      ),
    );
    if (leave != true) return;
    try {
      await ref
          .read(catechismApiProvider)
          .leaveTeacherClass(cls['id'] as String);
      if (mounted) setState(_load);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(error))),
        );
      }
    }
  }

  Future<void> _requestClass(_Row cls) async {
    try {
      await ref
          .read(catechismApiProvider)
          .requestTeacherApproval(cls['id'] as String);
      if (mounted) setState(_load);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Catechism teacher')),
        ),
        body: _WorkspaceData(
          future: _classes,
          retry: () => setState(_load),
          builder: (data) {
            final classes = _rows(data, 'classes');
            final available = _rows(data, 'availableClasses');
            return ListView(
              children: [
                ListTile(
                  title: Text(context.tr('Your assigned classes')),
                  subtitle: classes.isEmpty
                      ? Text(context.tr('No assigned classes'))
                      : null,
                ),
                for (final cls in classes.take(_pageSize))
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: Text(cls['name'] as String),
                    subtitle: Text(
                      "${cls['church']} · ${cls['substitute'] == true ? 'Substitute' : 'Teacher'}",
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: context.tr('Leave class'),
                          icon: const Icon(Icons.logout_outlined),
                          onPressed: () => _leaveClass(cls),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CatechismWorkspaceScreen(
                          classId: cls['id'] as String,
                          title: cls['name'] as String,
                        ),
                      ),
                    ),
                  ),
                if (available.isNotEmpty) ...[
                  ListTile(
                    title: Text(context.tr('Request access to more classes')),
                    subtitle: Text(context
                        .tr('Requests are reviewed by your Church Admin')),
                  ),
                  for (final cls in available)
                    if (cls['requestStatus'] != 'approved')
                      ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(cls['name'] as String? ?? ''),
                        subtitle: Text(switch (cls['requestStatus']) {
                          'pending' => context.tr('Request pending'),
                          'rejected' => context.tr('Request rejected'),
                          _ => context.tr('Available to request'),
                        }),
                        trailing: cls['requestStatus'] == 'pending'
                            ? const Icon(Icons.hourglass_top)
                            : TextButton(
                                onPressed: () => _requestClass(cls),
                                child: Text(context.tr('Request')),
                              ),
                      ),
                ],
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

  Future<void> _addNote() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _NoteComposer(onPublish: (title, description, file) async {
        final bytes = file.bytes;
        if (bytes == null) throw StateError('Could not read the selected PDF');
        await ref.read(catechismApiProvider).uploadNote(widget.classId,
            bytes: bytes,
            fileName: file.name,
            title: title,
            description: description);
      }),
    );
    if (result == true && mounted) setState(_load);
  }

  Future<void> _shareVideo() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TextEntryDialog(
        title: context.tr('Share class video'),
        fields: const [
          ('title', 'Video title'),
          ('description', 'Description'),
          ('url', 'HTTPS video link')
        ],
        save: (values) =>
            ref.read(catechismApiProvider).shareVideo(widget.classId, values),
      ),
    );
    if (result == true && mounted) setState(_load);
  }

  Future<void> _createTest() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TextEntryDialog(
        title: context.tr('Create test'),
        fields: const [('name', 'Test name'), ('maximum', 'Maximum marks')],
        save: (values) => ref.read(catechismApiProvider).createTest(
            widget.classId,
            values['name'] as String,
            int.tryParse(values['maximum'] as String) ?? 0),
      ),
    );
    if (result == true && mounted) setState(_load);
  }

  Future<void> _downloadNote(_Row material) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.tr('Save notes'),
        fileName: material['fileName'] as String? ?? 'class-notes.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (path == null) return;
      await ref
          .read(catechismApiProvider)
          .downloadMaterial(widget.classId, material['id'] as String, path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('Notes downloaded'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }

  Future<void> _deleteMaterial(_Row material) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete class material?')),
        content: Text(material['title'] as String),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Delete'))),
        ],
      ),
    );
    if (remove != true) return;
    try {
      await ref
          .read(catechismApiProvider)
          .deleteMaterial(widget.classId, material['id'] as String);
      if (mounted) setState(_load);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
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
    final requests = _rows(data, 'requests');
    final materials = _rows(data, 'materials');
    final tests = _rows(data, 'tests');
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
              OutlinedButton.icon(
                onPressed: _addNote,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(context.tr('Publish notes')),
              ),
              OutlinedButton.icon(
                onPressed: _shareVideo,
                icon: const Icon(Icons.video_library_outlined),
                label: Text(context.tr('Share class video')),
              ),
              OutlinedButton.icon(
                onPressed: _createTest,
                icon: const Icon(Icons.assignment_outlined),
                label: Text(context.tr('Create test')),
              ),
              OutlinedButton(
                onPressed: () => _edit(
                  'syllabus',
                  'Publish syllabus',
                  const [('title', 'Title'), ('body', 'Syllabus')],
                  initial: syllabus ?? const {},
                ),
                child: Text(syllabus == null
                    ? context.tr('Publish syllabus')
                    : context.tr('Update syllabus')),
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
              trailing: Text(teacher['substitute'] == true
                  ? context.tr('Substitute')
                  : context.tr('Teacher')),
            ),
        ],
        if (canTeach || canRegister) ...[
          ListTile(title: Text(context.tr('Admission requests'))),
          if (requests.isEmpty)
            ListTile(subtitle: Text(context.tr('No pending requests'))),
          for (final request in requests)
            Card(
                child: ListTile(
              title: Text(request['name'] as String),
              subtitle: Text(
                  '${request['dateOfBirth'] ?? ''}${request['notes'] == null ? '' : '\n${request['notes']}'}'),
              isThreeLine: request['notes'] != null,
              trailing: Wrap(alignment: WrapAlignment.end, children: [
                IconButton(
                    tooltip: context.tr('Approve'),
                    icon: const Icon(Icons.check_circle_outline),
                    onPressed: () async {
                      await ref
                          .read(catechismApiProvider)
                          .decideAdmission(request['id'] as String, 'approved');
                      if (mounted) setState(_load);
                    }),
                IconButton(
                    tooltip: context.tr('Reject'),
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () async {
                      await ref
                          .read(catechismApiProvider)
                          .decideAdmission(request['id'] as String, 'rejected');
                      if (mounted) setState(_load);
                    }),
              ]),
            )),
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
                publication['kind'] == 'syllabus'
                    ? context.tr('Syllabus')
                    : context.tr('Announcement'),
              ),
              subtitle: Text(publication['body'] as String),
            ),
          ),
        ListTile(
          title: Text(context.tr('Class materials')),
          trailing: IconButton(
            tooltip: context.tr('Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_load),
          ),
        ),
        if (materials.isEmpty)
          ListTile(subtitle: Text(context.tr('No class materials available'))),
        for (final material in materials)
          Card(
            child: ListTile(
              leading: Icon(material['kind'] == 'video'
                  ? Icons.play_circle_outline
                  : Icons.picture_as_pdf_outlined),
              title: Text(material['title'] as String),
              subtitle: Text([
                if ((material['description'] as String? ?? '').isNotEmpty)
                  material['description'] as String,
                if (material['fileName'] != null)
                  material['fileName'] as String,
              ].join('\n')),
              trailing: Wrap(
                children: [
                  if (material['kind'] == 'note')
                    IconButton(
                      tooltip: context.tr('Download notes'),
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () => _downloadNote(material),
                    )
                  else
                    IconButton(
                      tooltip: context.tr('Watch video'),
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => launchUrl(
                          Uri.parse(material['externalUrl'] as String),
                          mode: LaunchMode.externalApplication),
                    ),
                  if (canTeach || canRegister)
                    IconButton(
                      tooltip: context.tr('Delete'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteMaterial(material),
                    ),
                ],
              ),
            ),
          ),
        ListTile(title: Text(context.tr('Tests and marks'))),
        if (tests.isEmpty)
          ListTile(subtitle: Text(context.tr('No tests published yet'))),
        for (final test in tests)
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text(test['name'] as String),
              subtitle:
                  Text(context.tr('{0} marks recorded', [test['marksCount']])),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                builder: (_) => _TestMarksScreen(
                  classId: widget.classId,
                  testName: test['name'] as String,
                  canEdit: canTeach || canRegister,
                ),
              ))
                  .then((_) {
                if (mounted) setState(_load);
              }),
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

class _NoteComposer extends StatefulWidget {
  const _NoteComposer({required this.onPublish});
  final Future<void> Function(
      String title, String description, PlatformFile file) onPublish;
  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  PlatformFile? _file;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result != null && mounted) setState(() => _file = result.files.single);
  }

  Future<void> _save() async {
    final file = _file;
    if (_title.text.trim().isEmpty || file == null || file.bytes == null) {
      setState(() => _error = 'Enter a title and select a PDF file.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onPublish(
          _title.text.trim(), _description.text.trim(), file);
      if (mounted) Navigator.pop(context, true);
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
          title: Text(context.tr('Publish notes')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _title,
                  decoration: InputDecoration(labelText: context.tr('Title'))),
              TextField(
                  controller: _description,
                  decoration:
                      InputDecoration(labelText: context.tr('Description'))),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(_file?.name ?? context.tr('Select PDF notes')),
                onTap: _saving ? null : _pickFile,
              ),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(context.tr('Cancel'))),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? context.tr('Uploading...')
                    : context.tr('Publish'))),
          ],
        ),
      );
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog(
      {required this.title, required this.fields, required this.save});
  final String title;
  final List<(String, String)> fields;
  final Future<dynamic> Function(Map<String, dynamic>) save;
  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final (key, _) in widget.fields) key: TextEditingController(),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final values = <String, dynamic>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim()
    };
    if (values.values.any((value) => (value as String).isEmpty)) {
      setState(() => _error = 'Complete all fields.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(values);
      if (mounted) Navigator.pop(context, true);
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
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (key, label) in widget.fields)
              TextField(
                controller: _controllers[key],
                decoration: InputDecoration(labelText: context.tr(label)),
                keyboardType: key == 'maximum'
                    ? TextInputType.number
                    : TextInputType.text,
                maxLines: key == 'description' ? 3 : 1,
              ),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(context.tr('Cancel'))),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                    _saving ? context.tr('Saving...') : context.tr('Save'))),
          ],
        ),
      );
}

class _TestMarksScreen extends ConsumerStatefulWidget {
  const _TestMarksScreen(
      {required this.classId, required this.testName, required this.canEdit});
  final String classId;
  final String testName;
  final bool canEdit;
  @override
  ConsumerState<_TestMarksScreen> createState() => _TestMarksScreenState();
}

class _TestMarksScreenState extends ConsumerState<_TestMarksScreen> {
  late Future<_Row> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future =
      ref.read(catechismApiProvider).testMarks(widget.classId, widget.testName);

  Future<void> _editMark(_Row mark) async {
    final controller =
        TextEditingController(text: mark['score']?.toString() ?? '');
    final score = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('${widget.testName} · ${mark['studentName']}'),
              content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.tr('Score'))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('Cancel'))),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, int.tryParse(controller.text)),
                    child: Text(context.tr('Save'))),
              ],
            ));
    controller.dispose();
    if (score == null) return;
    try {
      await ref.read(catechismApiProvider).updateTestMark(widget.classId,
          widget.testName, mark['enrollmentId'] as String, score);
      if (mounted) setState(_load);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.testName)),
        body: FutureBuilder<_Row>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(_errorMessage(snapshot.error)));
              }
              final marks = _rows(snapshot.data!, 'marks');
              final test = snapshot.data!['test'] as _Row;
              return RefreshIndicator(
                  onRefresh: () async => setState(_load),
                  child: ListView(children: [
                    ListTile(
                        title: Text(context.tr('Maximum marks')),
                        trailing: Text('${test['maximum']}')),
                    for (final mark in marks)
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(mark['studentName'] as String),
                        subtitle: Text(mark['score'] == null
                            ? context.tr('No mark entered')
                            : '${mark['score']} / ${mark['maximum']}'),
                        trailing: widget.canEdit
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editMark(mark))
                            : null,
                      ),
                  ]));
            }),
      );
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
                ListTile(
                    subtitle: Text(context.tr('No attendance on this page'))),
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
                  TextButton(
                      onPressed: retry, child: Text(context.tr('Retry'))),
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
                Text(context
                    .tr('For an existing account, enter the email only.')),
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
                    DropdownMenuItem(
                        value: 'present', child: Text(context.tr('Present'))),
                    DropdownMenuItem(
                        value: 'absent', child: Text(context.tr('Absent'))),
                    DropdownMenuItem(
                        value: 'excused', child: Text(context.tr('Excused'))),
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
