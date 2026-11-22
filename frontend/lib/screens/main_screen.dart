import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../services/calendar_reminder_sync.dart';
import '../services/chat_notification_service.dart';
import '../services/chat_push_service.dart';
import 'admin_users_screen.dart';
import 'communities_screen.dart';
import 'social_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  Timer? _chatTimer;
  late final _chatNotifications = ref.read(chatNotificationServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReminders());
    _startChatPush();
    _startChatNotifications();
  }

  @override
  void dispose() {
    _stopChatNotifications();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncReminders();
      _startChatPush();
      _startChatNotifications();
    } else {
      _stopChatNotifications();
    }
  }

  void _startChatNotifications() {
    _chatTimer?.cancel();
    final foregroundStarted = DateTime.now();
    _chatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final user = ref.read(authProvider).user;
      if (user == null || !user.emailVerified) return;
      _chatNotifications.poll(user.id, (title, body) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$title\n$body',
                  maxLines: 3, overflow: TextOverflow.ellipsis)),
        );
      },
          notifySince:
              ref.read(chatPushProvider).registered ? foregroundStarted : null);
    });
  }

  void _startChatPush() {
    final user = ref.read(authProvider).user;
    if (user?.emailVerified == true) {
      unawaited(ref.read(chatPushProvider).start(user!.id));
    }
  }

  void _stopChatNotifications() {
    _chatTimer?.cancel();
    _chatNotifications.pause();
  }

  Future<void> _syncReminders() async {
    if (!ref.read(authProvider).isAuthenticated) return;
    final result = await syncCalendarReminders(ref);
    if (!mounted) return;
    showCalendarReminderPermissionHint(context, result);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authProvider
          .select((state) => (state.user?.id, state.user?.emailVerified)),
      (_, next) {
        _chatNotifications.pause();
        _startChatPush();
        ScaffoldMessenger.of(context).clearSnackBars();
      },
    );
    final user = ref.watch(authProvider).user;
    final isSuperAdmin = user?.role == 'super_admin';
    // Only regular members get the church-aware home page; super admins and
    // church staff do not have a personal "home" church tab.
    final useHome = user?.role == 'user';
    final churchId = user?.churchId;

    final tabs = <(Widget, BottomNavigationBarItem)>[
      if (useHome)
        const (
          HomeScreen(),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home')
        ),
      const (
        SearchScreen(),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search')
      ),
      (
        CommunitiesScreen(key: ValueKey((user?.id, churchId))),
        const BottomNavigationBarItem(
            icon: Icon(Icons.groups), label: 'Communities')
      ),
      (
        SocialScreen(key: ValueKey(user?.id)),
        const BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed_outlined), label: 'Feed'),
      ),
      if (isSuperAdmin)
        const (
          AdminUsersScreen(),
          BottomNavigationBarItem(
              icon: Icon(Icons.admin_panel_settings), label: 'Users')
        ),
      const (
        ProfileScreen(),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile')
      ),
    ];

    // Guard against an out-of-range index if the tab set changes (e.g. role
    // changes while the screen is mounted).
    final safeIndex = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: tabs[safeIndex].$1,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: [for (final tab in tabs) tab.$2],
      ),
    );
  }
}
