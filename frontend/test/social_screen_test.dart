import 'dart:convert';

import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/screens/social_screen.dart';
import 'package:believers_palace/services/social_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('My Posts can edit and delete a post after confirmation',
      (tester) async {
    final post = <String, dynamic>{
      'id': 'my-post',
      'name': 'Member',
      'username': 'member',
      'createdAt': '2026-01-01T00:00:00Z',
      'body': 'Original post',
      'liked': false,
      'likes': 0,
    };
    var deleted = false;
    var failEdit = true;
    final client = ApiClient(client: MockClient((request) async {
      switch ((request.method, request.url.path)) {
        case ('GET', '/api/social/feed'):
          return http.Response('{"data":[]}', 200);
        case ('GET', '/api/social/me/posts'):
          return http.Response(
              jsonEncode({
                'data': [if (!deleted) post]
              }),
              200);
        case ('PATCH', '/api/social/posts/my-post'):
          if (failEdit) {
            failEdit = false;
            return http.Response('{"message":"Technical detail"}', 500);
          }
          final changes = jsonDecode(request.body) as Map<String, dynamic>;
          post['body'] = changes['body'];
          return http.Response(jsonEncode({'body': post['body']}), 200);
        case ('DELETE', '/api/social/posts/my-post'):
          deleted = true;
          return http.Response('', 204);
        default:
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
      }
    }));
    await tester.pumpWidget(ProviderScope(
      overrides: [socialApiProvider.overrideWithValue(SocialApi(client))],
      child: const MaterialApp(home: SocialScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Posts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit post'));
    await tester.pumpAndSettle();
    expect(find.text('Original post'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Updated post');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save your post. Please try again.'),
        findsOneWidget);
    expect(find.textContaining('Technical detail'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Updated post'), findsOneWidget);

    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);

    await tester.tap(find.byTooltip('Post options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('Updated post'), findsNothing);
  });
}
