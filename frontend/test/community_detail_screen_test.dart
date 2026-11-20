import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:believers_palace/core/auth_provider.dart';
import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/models/community_models.dart';
import 'package:believers_palace/models/models.dart';
import 'package:believers_palace/screens/communities_screen.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:believers_palace/services/chat_live_service.dart';

class _TestChatLiveService extends ChatLiveService {
  _TestChatLiveService(super.api);

  final updates = StreamController<ChatChange?>.broadcast();

  @override
  Stream<ChatChange?> watch(String kind, String id) => updates.stream;

  @override
  void dispose() {
    unawaited(updates.close());
    super.dispose();
  }
}

class _CommunityApiService extends ApiService {
  _CommunityApiService(
      {this.incomingMessages = const [], this.communities = const []})
      : super(ApiClient());

  final List<CommunityMessage> incomingMessages;
  final List<Community> communities;
  final List<int?> afterCursors = [];
  bool _initialLatestRequested = false;

  @override
  Future<List<Community>> listCommunities() async => communities;

  @override
  Future<Community> createCommunity(
    String name,
    String description, {
    String? image,
  }) async =>
      Community(
        id: 'community-1',
        creatorId: 'owner-1',
        name: name,
        description: description,
        image: image,
        createdAt: DateTime.utc(2026),
        status: 'active',
        isAdmin: true,
      );

  @override
  Future<CommunityCursorPage> listCommunityMessages(
    String id, {
    int? before,
    int? after,
    int limit = 50,
  }) async {
    if (before != null) {
      final older =
          incomingMessages.where((message) => message.seq < before).toList();
      return CommunityCursorPage(
        data: older.take(limit).toList(),
        hasMore: older.length > limit,
      );
    }
    if (after == null && !_initialLatestRequested) {
      _initialLatestRequested = true;
      return const CommunityCursorPage(data: [], hasMore: false);
    }
    afterCursors.add(after);
    final matches = after == null
        ? incomingMessages
        : incomingMessages.where((message) => message.seq > after).toList();
    final window = matches.take(limit + 1).toList();
    return CommunityCursorPage(
      data: window.take(limit).toList(),
      hasMore: window.length > limit,
    );
  }

  @override
  Future<List<CommunityMembership>> listCommunityRequests(String id) async =>
      [];

  @override
  Future<List<CommunityMembership>> listCommunityMembers(String id) async => [
        CommunityMembership(
          id: 'membership-1',
          communityId: id,
          userId: 'owner-1',
          userName: 'Owner',
          status: 'active',
          isAdmin: true,
        ),
      ];
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super._api, {bool emailVerified = true}) {
    state = AuthState(
      user: User(
        id: 'owner-1',
        name: 'Owner',
        email: 'owner@example.test',
        emailVerified: emailVerified,
        role: 'user',
        createdAt: DateTime.utc(2026),
      ),
      isLoading: false,
    );
  }
}

void main() {
  testWidgets('Joined shows active memberships and administered communities',
      (tester) async {
    final api = _CommunityApiService(communities: [
      for (final (name, status, admin) in [
        ('Member group', 'active', false),
        ('Admin group', 'active', true),
        ('Pending group', 'pending', false),
        ('Open group', '', false),
      ])
        Community(
          id: name,
          creatorId: 'owner-1',
          name: name,
          description: '',
          createdAt: DateTime.utc(2026),
          status: status,
          isAdmin: admin,
        ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
          authProvider.overrideWith((ref) => _TestAuthNotifier(api)),
        ],
        child: const MaterialApp(home: CommunitiesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pending group'), findsOneWidget);
    expect(find.text('Open group'), findsOneWidget);

    await tester.tap(find.text('Joined'));
    await tester.pumpAndSettle();
    expect(find.text('Member group'), findsOneWidget);
    expect(find.text('Admin group'), findsOneWidget);
    expect(find.text('Pending group'), findsNothing);
    expect(find.text('Open group'), findsNothing);
  });

  testWidgets('creating a community opens its admin detail screen',
      (tester) async {
    final api = _CommunityApiService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
          authProvider.overrideWith((ref) => _TestAuthNotifier(api)),
        ],
        child: const MaterialApp(home: CommunitiesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Community picture (optional)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Test community');
    await tester.enterText(find.byType(TextField).at(1), 'A new group');
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Create'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test community'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified community admins see a verification prompt',
      (tester) async {
    final api = _CommunityApiService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
          authProvider.overrideWith(
            (ref) => _TestAuthNotifier(api, emailVerified: false),
          ),
        ],
        child: MaterialApp(
          home: CommunityDetailScreen(
            community: Community(
              id: 'community-1',
              creatorId: 'owner-1',
              name: 'Test community',
              description: 'A new group',
              createdAt: DateTime.utc(2026),
              status: 'active',
              isAdmin: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test community'), findsOneWidget);
    expect(find.text('Verify your email to access chat.'), findsOneWidget);
    expect(api._initialLatestRequested, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final useLive in [false, true]) {
    testWidgets(
        '${useLive ? 'Live delivery' : 'Fallback polling'} catches up all pages',
        (tester) async {
      final messages = List.generate(
        125,
        (index) => CommunityMessage(
          id: 'message-${index + 1}',
          communityId: 'community-1',
          seq: index + 1,
          userId: 'member-1',
          authorName: 'Member',
          content: 'Message ${index + 1}',
          createdAt: DateTime.utc(2026, 1, 1, 12, 0, index),
        ),
      );
      final api = _CommunityApiService(incomingMessages: messages);
      final live = _TestChatLiveService(api);
      addTearDown(live.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(api),
            authProvider.overrideWith((ref) => _TestAuthNotifier(api)),
            chatLiveProvider.overrideWithValue(live),
          ],
          child: MaterialApp(
            home: CommunityDetailScreen(
              community: Community(
                id: 'community-1',
                creatorId: 'owner-1',
                name: 'Test community',
                description: '',
                createdAt: DateTime.utc(2026),
                status: 'active',
                isAdmin: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (useLive) {
        live.updates.add((deleted: null));
        await tester.pump();
      } else {
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.pumpAndSettle();

      expect(api.afterCursors, [0, 50, 100]);
      expect(find.text('Message 125'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (useLive) {
        await tester.pump(const Duration(seconds: 4));
        expect(api.afterCursors, [0, 50, 100]);
      }
    });
  }
}
