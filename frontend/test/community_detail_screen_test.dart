import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:believers_palace/core/auth_provider.dart';
import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/models/community_models.dart';
import 'package:believers_palace/models/models.dart';
import 'package:believers_palace/screens/communities_screen.dart';
import 'package:believers_palace/services/api_service.dart';

class _CommunityApiService extends ApiService {
  _CommunityApiService() : super(ApiClient());

  @override
  Future<List<Community>> listCommunities() async => [];

  @override
  Future<Community> createCommunity(String name, String description) async =>
      Community(
        id: 'community-1',
        creatorId: 'owner-1',
        name: name,
        description: description,
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
  }) async =>
      const CommunityCursorPage(data: [], hasMore: false);

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
  _TestAuthNotifier(super._api) {
    state = AuthState(
      user: User(
        id: 'owner-1',
        name: 'Owner',
        email: 'owner@example.test',
        role: 'user',
        createdAt: DateTime.utc(2026),
      ),
      isLoading: false,
    );
  }
}

void main() {
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

  testWidgets('new admin community detail loads without child assertion',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(_CommunityApiService()),
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
    expect(tester.takeException(), isNull);
  });
}
