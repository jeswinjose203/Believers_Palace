import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../widgets/verify_email_banner.dart';
import 'admin_users_screen.dart';
import 'certificates_screen.dart';
import 'churches_screen.dart';
import 'home_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isSuperAdmin = user?.role == 'super_admin';
    // Only regular members get the church-aware home page; super admins and
    // church staff keep the churches list.
    final useHome = user?.role == 'user';

    final pages = <Widget>[
      // Members land on Search (index 0) right after login.
      if (useHome) const SearchScreen(),
      if (useHome) const HomeScreen() else const ChurchesScreen(),
      // Super admins manage bookings per church; they don't make their own.
      if (!isSuperAdmin) const MyBookingsScreen(),
      const CertificatesScreen(),
      if (isSuperAdmin) const AdminUsersScreen(),
      const ProfileScreen(),
    ];

    final items = <BottomNavigationBarItem>[
      if (useHome)
        const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
      if (useHome)
        const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home')
      else
        const BottomNavigationBarItem(
            icon: Icon(Icons.church), label: 'Churches'),
      if (!isSuperAdmin)
        const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today), label: 'My Bookings'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.school), label: 'Certificates'),
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
