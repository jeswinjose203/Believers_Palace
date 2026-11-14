import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import '../widgets/status_chip.dart';

class ManageEnrollmentsScreen extends ConsumerStatefulWidget {
  final String classId;

  const ManageEnrollmentsScreen({super.key, required this.classId});

  @override
  ConsumerState<ManageEnrollmentsScreen> createState() =>
      _ManageEnrollmentsScreenState();
}

class _ManageEnrollmentsScreenState extends ConsumerState<ManageEnrollmentsScreen> {
  Future<List<CatechismEnrollment>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref
        .read(catechismApiProvider)
        .listClassEnrollments(widget.classId, limit: 100)
        .then((p) => p.data);
  }

  Future<void> _setStatus(CatechismEnrollment e, String status) async {
    try {
      await ref.read(catechismApiProvider).updateEnrollmentStatus(e.id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked $status')));
        setState(_reload);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enrollments')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: FutureBuilder<List<CatechismEnrollment>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: ${snap.error}'),
                ),
              ]);
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const ListView(children: [
                SizedBox(height: 48),
                Center(child: Text('No enrollments yet.')),
              ]);
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.studentName, style: Theme.of(context).textTheme.titleMedium),
                        Text('DOB: ${DateFormat.yMMMd().format(e.dateOfBirth)}'),
                        if (e.notes != null && e.notes!.isNotEmpty) Text(e.notes!),
                        const SizedBox(height: 8),
                        CatechismStatusChip(status: e.status),
                        if (e.status == 'pending') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => _setStatus(e, 'approved'),
                                child: const Text('Approve'),
                              ),
                              TextButton(
                                onPressed: () => _setStatus(e, 'rejected'),
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ],
                        if (e.status == 'approved')
                          TextButton(
                            onPressed: () => _setStatus(e, 'completed'),
                            child: const Text('Mark completed'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}