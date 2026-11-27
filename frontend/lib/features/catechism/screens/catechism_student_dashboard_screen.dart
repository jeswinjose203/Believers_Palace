import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_locale.dart';
import '../../../models/models.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import '../widgets/status_chip.dart';
import 'catechism_list_screen.dart';
import 'catechism_workspace_screen.dart';

class CatechismStudentDashboardScreen extends ConsumerStatefulWidget {
  const CatechismStudentDashboardScreen({super.key, required this.churchId});
  final String churchId;

  @override
  ConsumerState<CatechismStudentDashboardScreen> createState() =>
      _CatechismStudentDashboardScreenState();
}

class _CatechismStudentDashboardScreenState
    extends ConsumerState<CatechismStudentDashboardScreen> {
  late Future<PaginatedResponse<CatechismEnrollment>> _enrollments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _enrollments = ref.read(catechismApiProvider).listMyEnrollments(limit: 100);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Student / Parent dashboard'))),
        body: FutureBuilder<PaginatedResponse<CatechismEnrollment>>(
          future: _enrollments,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: Text(context.tr('Retry')),
                  ),
                ]),
              );
            }
            final items = snapshot.data!.data;
            return RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(context.tr('My classes'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(context.tr('No class requests yet')),
                        subtitle: Text(context.tr(
                            'Browse classes and request admission for a student.')),
                      ),
                    ),
                  for (final item in items)
                    Card(
                      child: ListTile(
                        leading: Icon(item.status == 'approved'
                            ? Icons.menu_book_outlined
                            : Icons.hourglass_top_outlined),
                        title: Text(item.studentName),
                        subtitle: Text(item.className ?? item.classId),
                        trailing: CatechismStatusChip(status: item.status),
                        onTap: item.status == 'approved' ||
                                item.status == 'completed'
                            ? () =>
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => CatechismWorkspaceScreen(
                                    classId: item.classId,
                                    title: item.className ??
                                        context.tr('Class workspace'),
                                  ),
                                ))
                            : null,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                CatechismListScreen(churchId: widget.churchId),
                          ),
                        )
                        .then((_) => setState(_load)),
                    icon: const Icon(Icons.search),
                    label: Text(context.tr('Browse available classes')),
                  ),
                ],
              ),
            );
          },
        ),
      );
}
