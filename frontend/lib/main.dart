import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth_provider.dart';
import 'services/calendar_notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const ProviderScope(child: BelieversPalaceApp()));
}

class BelieversPalaceApp extends ConsumerStatefulWidget {
  const BelieversPalaceApp({super.key});

  @override
  ConsumerState<BelieversPalaceApp> createState() => _BelieversPalaceAppState();
}

class _BelieversPalaceAppState extends ConsumerState<BelieversPalaceApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(authProvider.notifier).init();
      await CalendarNotificationService.instance.init();
    });
  }
 
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return MaterialApp(
      title: 'Believers Palace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: auth.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : auth.isAuthenticated
              ? const MainScreen()
              : const LoginScreen(),
    );
  }
}
