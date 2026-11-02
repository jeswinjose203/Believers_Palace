import 'package:flutter/material.dart';

import '../widgets/verify_email_banner.dart';
import 'certificates_screen.dart';
import 'churches_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  final _pages = const [
    ChurchesScreen(),
    MyBookingsScreen(),
    CertificatesScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const VerifyEmailBanner(),
            Expanded(child: _pages[_index]),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.church), label: 'Churches'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'My Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.school), label: 'Certificates'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
