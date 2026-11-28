import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth_provider.dart';
import '../../../l10n/app_locale.dart';
import '../../../models/models.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import 'catechism_student_dashboard_screen.dart';
import 'catechism_list_screen.dart';
import 'catechism_workspace_screen.dart';

class CatechismEntryScreen extends ConsumerWidget {
  const CatechismEntryScreen({super.key, required this.churchId});
  final String churchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isAdmin =
        user?.role == 'church_admin' && user?.churchId == churchId ||
            user?.role == 'super_admin';
    return Scaffold(
      appBar: AppBar(
          title: Text(context.tr('Catechism')),
          leading: Navigator.of(context).canPop() ? const BackButton() : null),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
            child: ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(context.tr('Enter as Teacher')),
                subtitle: Text(context.tr('Open your assigned classes')),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CatechismTeacherScreen())))),
        if (!isAdmin)
          Card(
            child: ListTile(
                leading: const Icon(Icons.family_restroom),
                title: Text(context.tr('Enter as Student / Parent')),
                subtitle: Text(
                    context.tr('Browse classes and manage admission requests')),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CatechismStudentDashboardScreen(
                            churchId: churchId))))),
        if (isAdmin)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.class_outlined),
                  title: Text(context.tr('Manage Catechism classes')),
                  subtitle:
                      Text(context.tr('Create and manage church classes')),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              CatechismListScreen(churchId: churchId))))),
        if (isAdmin)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(context.tr('Assign Catechism teachers')),
                  subtitle: Text(
                      context.tr('Choose registered members of this church')),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              _TeacherAssignments(churchId: churchId))))),
      ]),
    );
  }
}

class _TeacherAssignments extends ConsumerStatefulWidget {
  const _TeacherAssignments({required this.churchId});
  final String churchId;
  @override
  ConsumerState<_TeacherAssignments> createState() =>
      _TeacherAssignmentsState();
}

class _TeacherAssignmentsState extends ConsumerState<_TeacherAssignments> {
  late Future<PaginatedResponse<CatechismClass>> _classes;
  late Future<Map<String, dynamic>> _members;
  String? _classId;
  final Set<String> _assigned = {};
  final Set<String> _removed = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _classes =
        ref.read(catechismApiProvider).listClasses(widget.churchId, limit: 100);
    _members = ref
        .read(catechismApiProvider)
        .teacherCandidates(widget.churchId, _classId);
  }

  Future<void> _assign(String userId, bool value) async {
    final classId = _classId;
    if (classId == null) return;
    await ref
        .read(catechismApiProvider)
        .assignTeacher(widget.churchId, classId, userId, remove: !value);
    if (!mounted) return;
    setState(() {
      if (value) {
        _assigned.add(userId);
        _removed.remove(userId);
      } else {
        _assigned.remove(userId);
        _removed.add(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Assign Catechism teachers'))),
        body: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(tabs: [
              Tab(text: context.tr('Assignments')),
              Tab(text: context.tr('Accept requests')),
            ]),
          ),
          Expanded(child: TabBarView(children: [
            FutureBuilder<PaginatedResponse<CatechismClass>>(
          future: _classes,
          builder: (context, classes) {
            if (classes.hasError) {
              return Center(child: Text(classes.error.toString()));
            }
            if (!classes.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = classes.data!.data;
            if (items.isEmpty) {
              return Center(child: Text(context.tr('No classes yet.')));
            }
            _classId ??= items.first.id;
            return Column(children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                      initialValue: _classId,
                      decoration:
                          InputDecoration(labelText: context.tr('Class')),
                      items: [
                        for (final item in items)
                          DropdownMenuItem(
                              value: item.id, child: Text(item.name))
                      ],
                      onChanged: (value) => setState(() {
                            _classId = value;
                            _assigned.clear();
                            _removed.clear();
                            _members = ref
                                .read(catechismApiProvider)
                                .teacherCandidates(widget.churchId, value);
                          }))),
              Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                      future: _members,
                      builder: (context, members) {
                        if (members.hasError) {
                          return Center(child: Text(members.error.toString()));
                        }
                        if (!members.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final list =
                            (members.data!['members'] as List<dynamic>? ?? [])
                                .cast<Map<String, dynamic>>();
                        if (list.isEmpty) {
                          return Center(
                              child: Text(context.tr('No members found')));
                        }
                        return ListView(children: [
                          for (final member in list)
                            CheckboxListTile(
                                title: Text(member['name'] as String),
                                subtitle: Text(member['email'] as String),
                                value: _assigned.contains(member['id']) ||
                                    (member['assigned'] == true &&
                                        !_removed.contains(member['id'])),
                                onChanged: (value) async {
                                  try {
                                    await _assign(
                                        member['id'] as String, value == true);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(e.toString())));
                                    }
                                  }
                                })
                        ]);
                      }))
            ]);
          },
            ),
            _TeacherRequestsScreen(churchId: widget.churchId),
          ])),
        ]),
        ),
      );
}

class _TeacherRequestsScreen extends ConsumerStatefulWidget {
  const _TeacherRequestsScreen({required this.churchId});
  final String churchId;

  @override
  ConsumerState<_TeacherRequestsScreen> createState() =>
      _TeacherRequestsScreenState();
}

class _TeacherRequestsScreenState
    extends ConsumerState<_TeacherRequestsScreen> {
  late Future<Map<String, dynamic>> _requests;
  late Future<PaginatedResponse<CatechismClass>> _classes;
  final Map<String, String?> _classByRequest = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = ref.read(catechismApiProvider);
    _requests = api.teacherRequests(widget.churchId);
    _classes = api.listClasses(widget.churchId, limit: 100);
  }

  Future<void> _review(String id, String status, String? classId) async {
    try {
      await ref.read(catechismApiProvider).reviewTeacherRequest(
            widget.churchId,
            id,
            status: status,
            classId: classId,
          );
      if (mounted) setState(_load);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
          future: _requests,
          builder: (context, requestsSnapshot) {
            if (requestsSnapshot.hasError) {
              return Center(child: Text(requestsSnapshot.error.toString()));
            }
            if (!requestsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests =
                (requestsSnapshot.data!['requests'] as List<dynamic>? ?? [])
                    .cast<Map<String, dynamic>>();
            if (requests.isEmpty) {
              return Center(
                  child: Text(context.tr('No pending teacher requests')));
            }
            return FutureBuilder<PaginatedResponse<CatechismClass>>(
              future: _classes,
              builder: (context, classesSnapshot) {
                if (classesSnapshot.hasError) {
                  return Center(child: Text(classesSnapshot.error.toString()));
                }
                if (!classesSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final classes = classesSnapshot.data!.data;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final request in requests)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.person_outline),
                                title: Text(request['name'] as String? ?? ''),
                                subtitle: Text([
                                  request['email'] as String? ?? '',
                                  if ((request['className'] as String? ?? '')
                                      .isNotEmpty)
                                    '${context.tr('Requested class')}: ${request['className']}',
                                ].join('\n')),
                              ),
                              if ((request['classId'] as String? ?? '')
                                      .isEmpty &&
                                  classes.isNotEmpty)
                                DropdownButtonFormField<String>(
                                  initialValue:
                                      _classByRequest[request['id']] ??
                                          classes.first.id,
                                  decoration: InputDecoration(
                                      labelText: context.tr('Assign to class')),
                                  items: [
                                    for (final cls in classes)
                                      DropdownMenuItem(
                                          value: cls.id, child: Text(cls.name)),
                                  ],
                                  onChanged: (value) => setState(() =>
                                      _classByRequest[request['id'] as String] =
                                          value),
                                )
                              else if ((request['classId'] as String? ?? '')
                                  .isEmpty)
                                Text(context.tr(
                                    'Create a class before approving this request')),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: classes.isEmpty &&
                                            (request['classId'] as String? ??
                                                    '')
                                                .isEmpty
                                        ? null
                                        : () => _review(
                                              request['id'] as String,
                                              'approved',
                                              request['classId'] as String? ??
                                                  _classByRequest[
                                                      request['id']] ??
                                                  classes.first.id,
                                            ),
                                    icon: const Icon(Icons.check),
                                    label: Text(context.tr('Approve')),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _review(
                                        request['id'] as String,
                                        'rejected',
                                        null),
                                    icon: const Icon(Icons.close),
                                    label: Text(context.tr('Reject')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
}
