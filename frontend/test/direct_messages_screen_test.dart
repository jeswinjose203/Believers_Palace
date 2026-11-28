import 'dart:async';
import 'dart:convert';

import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/core/auth_provider.dart';
import 'package:believers_palace/models/models.dart';
import 'package:believers_palace/screens/direct_messages_screen.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:believers_palace/services/chat_live_service.dart';
import 'package:believers_palace/services/social_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthNotifier {
  _SignedIn(super.api) {
    state = AuthState(
      user: User(
        id: 'sender',
        name: 'Sender',
        email: 'sender@example.test',
        role: 'user',
        createdAt: DateTime.utc(2026),
      ),
    );
  }
}

class _QuietChatLive extends ChatLiveService {
  _QuietChatLive(super.api);

  @override
  Stream<ChatChange?> watch(String kind, String id) => const Stream.empty();
}

void main() {
  testWidgets('sending keeps the composer focused and preserves the next draft',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final send = Completer<http.Response>();
    final saved = {
      'seq': 1,
      'senderId': 'sender',
      'body': 'First message',
      'createdAt': '2026-01-01T00:00:00Z',
    };
    var accepted = false;
    var readThrough = 0;
    final attempts = <String>[];
    final client = ApiClient(client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/social/threads':
          return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'thread',
                    'peerId': 'recipient',
                    'name': 'Recipient',
                    'username': 'recipient',
                    'preview': 'Hello',
                  }
                ],
              }),
              200);
        case '/api/social/me':
          return http.Response('{}', 200);
        case '/api/social/threads/thread/messages':
          return http.Response(
              jsonEncode({
                'data': [if (accepted) saved],
                'peerReadThrough': readThrough,
              }),
              200);
        case '/api/social/messages':
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['body'], 'First message');
          attempts.add(body['clientId'] as String);
          if (attempts.length == 1) throw http.ClientException('Offline');
          return send.future;
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
    }));
    final api = ApiService(client);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((_) => _SignedIn(api)),
        socialApiProvider.overrideWithValue(SocialApi(client)),
        chatLiveProvider.overrideWithValue(_QuietChatLive(api)),
      ],
      child: const MaterialApp(home: DirectMessagesScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipient'));
    await tester.pumpAndSettle();

    final input = find.widgetWithText(TextField, 'Message');
    await tester.enterText(input, 'First message');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.widget<TextField>(input).enabled, isNot(false));
    expect(find.byIcon(Icons.check), findsOneWidget);

    tester.testTextInput.enterText('Next message');
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(attempts, hasLength(2));
    expect(attempts[1], attempts[0]);
    accepted = true;
    send.complete(
        http.Response(jsonEncode({'id': 'thread', 'message': saved}), 201));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.widget<TextField>(input).controller?.text, 'Next message');
    final ticks = find.byIcon(Icons.done_all);
    expect(tester.widget<Icon>(ticks).semanticLabel, 'Sent');
    readThrough = 1;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(ticks).semanticLabel, 'Seen');
    expect(tester.widget<Icon>(ticks).color, Colors.blue);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
