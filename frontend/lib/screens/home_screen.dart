import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/today_schedule_card.dart';
import 'church_detail_screen.dart';
import 'churches_screen.dart';
import 'dart:async';
 
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
                  Text(context.tr('Could not load your church: {0}', [snapshot.error]),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _reload(churchId),
                    child: Text(context.tr('Retry')),
                  ),
                  TextButton(
                    onPressed: _chooseChurch,
                    child: Text(context.tr('Choose another church')),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
  children: [
    _FadeSlideIn(
      delay: const Duration(milliseconds: 100),
      child: const TodayScheduleCard(),
    ),

    Expanded(
      child: _FadeSlideIn(
        delay: const Duration(milliseconds: 250),
        child: ChurchDetailScreen(
          key: ValueKey(churchId),
          church: snapshot.data!,
          isHome: true,
        ),
      ),
    ),
  ],
);
      },
    );
  }
}
 class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _FadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _position = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(widget.delay);

    if (mounted) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _position,
        child: widget.child,
      ),
    );
  }
}