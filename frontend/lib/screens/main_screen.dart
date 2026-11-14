import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
 
import '../core/auth_provider.dart';
import '../widgets/verify_email_banner.dart';
import 'admin_users_screen.dart';
import 'certificates_screen.dart';
import 'calendar_screen.dart';
import 'communities_screen.dart';
import 'home_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import '../features/catechism/screens/catechism_list_screen.dart';
import '../features/catechism/screens/my_enrollments_screen.dart';
 
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
    // church staff do not have a personal "home" church tab.
    final useHome = user?.role == 'user';
    final churchId = user?.churchId;
    final hasChurch = churchId != null && churchId.isNotEmpty;
 
    final pages = <Widget>[
      // Everyone lands on the shared "Find your church" search page. Admins and
      // super admins get church management actions (Add/Edit/Delete) inline on
      // that same screen; regular members get the heart ("set my church").
      const SearchScreen(),
      const CommunitiesScreen(),
      const CalendarScreen(),
      if (hasChurch)
        CatechismListScreen(churchId: churchId!)
      else
        const MyEnrollmentsScreen(),
      if (useHome) const HomeScreen(),
      // Super admins manage bookings per church; they don't make their own.
      if (!isSuperAdmin) const MyBookingsScreen(),
      const CertificatesScreen(),
      if (isSuperAdmin) const AdminUsersScreen(),
      const ProfileScreen(),
    ];
 
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.groups), label: 'Communities'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month), label: 'Calendar'),
      BottomNavigationBarItem(
        icon: const Icon(Icons.menu_book_outlined),
        label: hasChurch ? 'Catechism' : 'Enrollments',
      ),
      if (useHome)
        const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
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
 