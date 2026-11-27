import 'dart:convert';

import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/l10n/app_locale.dart';
import 'package:believers_palace/screens/login_screen.dart';
import 'package:believers_palace/screens/social_post.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:believers_palace/services/social_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Malayalam can be selected and restored on sign-in',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    Widget app(ProviderContainer container) => UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, child) => MaterialApp(
              locale: ref.watch(appLocaleProvider),
              supportedLocales: supportedAppLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const LoginScreen(),
            ),
          ),
        );

    final first = ProviderContainer();
    addTearDown(first.dispose);
    await tester.pumpWidget(app(first));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('മലയാളം'));
    await tester.pumpAndSettle();

    final login = find.text('പ്രവേശിക്കുക');
    expect(login, findsOneWidget);
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.text('ഇമെയിൽ വിലാസവും പാസ്‌വേഡും നൽകുക'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    await restored.read(appLocaleProvider.notifier).restore();
    await tester.pumpWidget(app(restored));
    await tester.pumpAndSettle();
    expect(login, findsOneWidget);

    await tester.tap(find.text('മലയാളം'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('A shared chat post opens the original feed post',
      (tester) async {
    const id = '1c0fe5e7-dd2a-4e9a-868c-7af20652ed57';
    final client = ApiClient(client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, endsWith('/social/posts/$id'));
      return http.Response(
          jsonEncode({
            'id': id,
            'name': 'Alice',
            'username': 'Alice_01',
            'body': 'Original post',
            'createdAt': '2026-01-01T12:00:00Z',
            'likes': 3,
            'liked': false,
            'comments': 2,
            'recentLiker': 'Bob_02',
          }),
          200);
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp(
          home: Scaffold(
        body: SharedPostMessage(sharedPostReference(id)),
      )),
    ));
    await tester.tap(find.text('View shared post'));
    await tester.pumpAndSettle();
    expect(find.text('Original post'), findsOneWidget);
    expect(find.text('3 likes'), findsOneWidget);
    expect(find.text('2 comments'), findsOneWidget);
    expect(find.text('Liked by @Bob_02 and others'), findsOneWidget);
  });

  testWidgets('Login validates missing credentials locally', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(find.text('Please enter your email and password'), findsOneWidget);
  });
}
