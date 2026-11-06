import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'church_detail_screen.dart';
import 'churches_screen.dart';

/// Home tab for non-super-admin users.
///
/// - User has selected a church: show that church's page (About, announcements,
///   events, ...) as the home page.
/// - No church selected: show the church list with a prompt to pick one.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _loadedFor;
  Future<Church>? _future;

  Future<Church> _load(String churchId) =>
      ref.read(apiServiceProvider).getChurch(churchId);

  void _reload(String churchId) {
    setState(() => _future = _load(churchId));
  }

  Future<void> _chooseChurch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const ChurchesScreen(selectMode: true, popOnSelect: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final churchId = ref.watch(authProvider.select((s) => s.user?.churchId));

    if (churchId == null || churchId.isEmpty) {
      _loadedFor = null;
      _future = null;
      return const ChurchesScreen(selectMode: true);
    }

    if (_loadedFor != churchId) {
      _loadedFor = churchId;
      _future = _load(churchId);
    }

    return FutureBuilder<Church>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load your church: ${snapshot.error}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _reload(churchId),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: _chooseChurch,
                    child: const Text('Choose another church'),
                  ),
                ],
              ),
            ),
          );
        }
        return ChurchDetailScreen(
          key: ValueKey(churchId),
          church: snapshot.data!,
          isHome: true,
        );
      },
    );
  }
}
