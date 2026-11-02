import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import 'admin_users_screen.dart' show roleLabel;

/// A small dashboard summarizing user counts by role, shown at the top of the
/// admin Users tab. Counts are derived from the paginated `/users` endpoint's
/// `total` (one lightweight call per role plus a total), so no backend change
/// is required.
class UserStatsDashboard extends ConsumerStatefulWidget {
  /// Bumping this value triggers a reload (e.g. after a role change).
  final int refreshToken;

  const UserStatsDashboard({super.key, this.refreshToken = 0});

  @override
  ConsumerState<UserStatsDashboard> createState() => _UserStatsDashboardState();
}

class _UserStatsDashboardState extends ConsumerState<UserStatsDashboard> {
  static const _roles = [
    'user',
    'priest',
    'associate_priest',
    'church_admin',
    'super_admin',
  ];

  Future<_Stats>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant UserStatsDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      setState(() => _future = _load());
    }
  }

  Future<_Stats> _load() async {
    final stats = await ref.read(apiServiceProvider).getUserStats();
    return _Stats(
      total: stats.total,
      byRole: {for (final r in _roles) r: stats.countFor(r)},
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Stats>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load stats: ${snapshot.error}'),
          );
        }
        final stats = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TotalCard(total: stats.total),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AdminsCard(
                      churchAdmins: stats.byRole['church_admin'] ?? 0,
                      superAdmins: stats.byRole['super_admin'] ?? 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Users by role',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _RoleBarChart(
                data: [
                  for (final r in _roles)
                    _Bar(roleLabel(r), stats.byRole[r] ?? 0),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stats {
  final int total;
  final Map<String, int> byRole;

  _Stats({required this.total, required this.byRole});
}

class _TotalCard extends StatelessWidget {
  final int total;

  const _TotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.people),
            const SizedBox(height: 8),
            Text('$total',
                style: Theme.of(context).textTheme.headlineMedium),
            const Text('Total users'),
          ],
        ),
      ),
    );
  }
}

class _AdminsCard extends StatelessWidget {
  final int churchAdmins;
  final int superAdmins;

  const _AdminsCard({required this.churchAdmins, required this.superAdmins});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, size: 20),
                const SizedBox(width: 8),
                Text('$superAdmins', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 6),
                const Expanded(child: Text('Super admins')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 20),
                const SizedBox(width: 8),
                Text('$churchAdmins', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 6),
                const Expanded(child: Text('Church admins')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar {
  final String label;
  final int value;

  _Bar(this.label, this.value);
}

/// A compact horizontal bar chart drawn without any external chart package.
class _RoleBarChart extends StatelessWidget {
  final List<_Bar> data;

  const _RoleBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxValue =
        data.fold<int>(0, (m, b) => b.value > m ? b.value : m);
    final color = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        for (final b in data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(b.label,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fraction =
                          maxValue == 0 ? 0.0 : b.value / maxValue;
                      return Stack(
                        children: [
                          Container(
                            height: 20,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: fraction.clamp(0.0, 1.0),
                            child: Container(
                              height: 20,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  child: Text('${b.value}',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
