import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth_provider.dart';
import 'l10n/app_locale.dart';
import 'features/catechism/screens/catechism_workspace_screen.dart';
import 'providers/calendar_provider.dart';
import 'services/calendar_notification_service.dart';
import 'services/android_update_service.dart';
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
  final _navigator = GlobalKey<NavigatorState>();
  late final _updates = AndroidUpdatePrompter(_navigator);

  @override
  void initState() {
    super.initState();
    _updates.start();
    Future.microtask(() async {
      await ref.read(appLocaleProvider.notifier).restore();
      if (!mounted) return;
      await ref.read(authProvider.notifier).init();
      await CalendarNotificationService.instance.init();
    });
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  void _onAuthSessionChange(AuthState? prev, AuthState next) {
    final prevUserId = prev?.user?.id;
    final nextUserId = next.user?.id;
    if (prevUserId != nextUserId) {
      ref.read(calendarProvider.notifier).reset();
      if (nextUserId == null) {
        CalendarNotificationService.instance.clearForLogout();
      }
    } else if (prev?.user?.churchId != next.user?.churchId) {
      ref.read(calendarProvider.notifier).refreshSchedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    ref.listen<AuthState>(authProvider, _onAuthSessionChange);

    return MaterialApp(
      navigatorKey: _navigator,
      locale: ref.watch(appLocaleProvider),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'Believers Palace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: auth.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : auth.isAuthenticated
              ? (auth.teacherMode
                  ? const CatechismTeacherScreen()
                  : const MainScreen())
              : const LoginScreen(),
    );
  }
}
