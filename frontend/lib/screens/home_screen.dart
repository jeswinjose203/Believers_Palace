import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/auth_provider.dart';
import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'church_detail_screen.dart';
import 'churches_screen.dart';

/// Shows the signed-in member's selected church. Members without a church are
/// routed to Search by MainScreen, so this is only a defensive empty state.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _loadedChurchId;
  Future<Church>? _churchFuture;

  @override
  Widget build(BuildContext context) {
    final churchId = ref.watch(authProvider.select((state) => state.user?.churchId));
    if (churchId == null || churchId.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.tr('Choose a church to see your home page.')),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ChurchesScreen(selectMode: true, popOnSelect: true),
              )),
              child: Text(context.tr('Find a church')),
            ),
          ]),
        ),
      );
    }
    if (_loadedChurchId != churchId) {
      _loadedChurchId = churchId;
      _churchFuture = ref.read(apiServiceProvider).getChurch(churchId);
    }
    return FutureBuilder<Church>(
      future: _churchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(child: Text(context.tr('Could not load your church.'))),
          );
        }
        return ChurchDetailScreen(church: snapshot.data!, isHome: true);
      },
    );
  }
}
