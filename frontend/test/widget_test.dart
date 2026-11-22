import 'dart:convert';

import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/screens/login_screen.dart';
import 'package:believers_palace/screens/social_post.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:believers_palace/services/social_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
