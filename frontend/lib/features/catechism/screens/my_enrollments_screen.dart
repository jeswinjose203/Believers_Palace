import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import '../widgets/status_chip.dart';

class MyEnrollmentsScreen extends ConsumerStatefulWidget {
  const MyEnrollmentsScreen({super.key});

  @override
  ConsumerState<MyEnrollmentsScreen> createState() => _MyEnrollmentsScreenState();
}

class _MyEnrollmentsScreenState extends ConsumerState<MyEnrollmentsScreen> {
  Future<List<CatechismEnrollment>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref
        .read(catechismApiProvider)
        .listMyEnrollments(limit: 50)
        .then((p) => p.data);
  }

  Future<void> _withdraw(CatechismEnrollment e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw enrollment?'),
        content: Text('Withdraw ${e.studentName} from ${e.className ?? 'this class'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(catechismApiProvider).withdrawEnrollment(e.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawn')));
        setState(_reload);
      }
    } on ApiException catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My enrollments')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_reload),
        child: FutureBuilder<List<CatechismEnrollment>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text('Error: ${snap.error}'),
                        FilledButton(onPressed: () => setState(_reload), child: const Text('Retry')),
                      ],
                    ),
                  ),
                ],
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const ListView(children: [
                SizedBox(height: 48),
                Center(child: Text('No enrollments yet.')),
              ]);
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                final canWithdraw = e.status == 'pending' || e.status == 'approved';
                return Card(
                  child: ListTile(
                    title: Text(e.studentName),
                    subtitle: Text(
                      '${e.className ?? e.classId}\nDOB: ${DateFormat.yMMMd().format(e.dateOfBirth)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CatechismStatusChip(status: e.status),
                        if (canWithdraw)
                          TextButton(onPressed: () => _withdraw(e), child: const Text('Withdraw')),
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