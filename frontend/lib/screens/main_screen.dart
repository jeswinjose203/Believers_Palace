import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../services/calendar_reminder_sync.dart';
import '../widgets/verify_email_banner.dart';
import 'admin_users_screen.dart';
import 'communities_screen.dart';
import 'marketplace_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReminders());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncReminders();
    }
  }

  Future<void> _syncReminders() async {
    if (!ref.read(authProvider).isAuthenticated) return;
    final result = await syncCalendarReminders(ref);
    if (!mounted) return;
    showCalendarReminderPermissionHint(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isSuperAdmin = user?.role == 'super_admin';
    // Only regular members get the church-aware home page; super admins and
    // church staff do not have a personal "home" church tab.
    final useHome = user?.role == 'user';

    final pages = <Widget>[
      if (useHome) const HomeScreen(),
      // Everyone lands on the shared "Find your church" search page. Admins and
      // super admins get church management actions (Add/Edit/Delete) inline on
      // that same screen; regular members get the heart ("set my church").
      const SearchScreen(),
      const CommunitiesScreen(),
      const MarketplaceScreen(),
      if (isSuperAdmin) const AdminUsersScreen(),
      const ProfileScreen(),
    ];

    final items = <BottomNavigationBarItem>[
      if (useHome)
        const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.groups), label: 'Communities'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.storefront), label: 'Marketplace'),
      if (isSuperAdmin)
        const BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings), label: 'Users'),
      const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
    ];

    // Guard against an out-of-range index if the tab set changes (e.g. role
    // changes while the screen is mounted).
    final safeIndex = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const VerifyEmailBanner(),
            Expanded(child: pages[safeIndex]),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: items,
      ),
    );
  }
}
