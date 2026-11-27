import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth_provider.dart';
import '../../../l10n/app_locale.dart';
import '../../../models/models.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import 'catechism_student_dashboard_screen.dart';
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Assign Catechism teachers'))),
        body: FutureBuilder<PaginatedResponse<CatechismClass>>(
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
      );
}
