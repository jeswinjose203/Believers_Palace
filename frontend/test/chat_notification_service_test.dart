import 'package:believers_palace/core/api_client.dart';
import 'package:believers_palace/models/community_models.dart';
import 'package:believers_palace/models/models.dart';
import 'package:believers_palace/services/api_service.dart';
import 'package:believers_palace/services/chat_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ChatApi extends ApiService {
  _ChatApi() : super(ApiClient());

  @override
  Future<List<Community>> listCommunities() async => [];

  @override
  Future<ChatCursorPage> listEventMessagesCursor(
    String eventId, {
    int? before,
    int? after,
    int limit = 50,
  }) async {
    expect(after, 7);
    return ChatCursorPage(
      data: [
        for (final (seq, sender) in [(8, 'me'), (9, 'other')])
          ChatMessage(
            id: '$eventId-$seq',
            eventId: eventId,
            seq: seq,
            userId: sender,
            authorName: 'Member',
            content: 'Message $seq',
            createdAt: DateTime.now(),
          ),
      ],
      hasMore: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notifies for incoming messages and stores mute per account and chat', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _ChatApi();
    final service = ChatNotificationService(api);
    await service.followEvent('me', 'one', 'First event', 7);
    await service.followEvent('me', 'two', 'Second event', 7);
    await service.setMuted('me', ChatKind.event, 'two', true);

    final received = <(String, String)>[];
    void record(String title, String body) => received.add((title, body));
    await service.poll('me', record);
    await service.poll('me', record);

    expect(received, [('First event', 'Member: Message 9')]);
    final reopened = ChatNotificationService(api);
    expect(await reopened.muted('me', ChatKind.event, 'two'), isTrue);
    expect(await reopened.muted('other', ChatKind.event, 'two'), isFalse);
    expect(await reopened.muted('me', ChatKind.community, 'two'), isFalse);
    await reopened.setMuted('me', ChatKind.event, 'two', false);
    expect(await reopened.muted('me', ChatKind.event, 'two'), isFalse);
  });
}
