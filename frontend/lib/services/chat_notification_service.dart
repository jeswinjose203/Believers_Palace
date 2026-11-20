import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import 'api_service.dart';
import 'calendar_notification_service.dart';

enum ChatKind { community, event }

typedef ChatNotice = ({
  int seq,
  String? senderId,
  String author,
  String body,
  DateTime sentAt,
});

final chatNotificationServiceProvider = Provider<ChatNotificationService>(
  (ref) => ChatNotificationService(ref.watch(apiServiceProvider)),
);

class ChatNotificationService {
  ChatNotificationService(this._api);

  final ApiService _api;
  final Map<({ChatKind kind, String id}), DateTime> _lastPolled = {};
  DateTime? _lastDiscovery;
  Map<String, String> _communities = {};
  String? _userId;
  bool _busy = false;
  int _session = 0;

  String _key(String user, ChatKind kind, String id) =>
      'chat_notifications.$user.${kind.name}.$id';

  Future<bool> muted(String user, ChatKind kind, String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('${_key(user, kind, id)}.enabledAt') == -1;
  }

  Future<void> setMuted(
    String user,
    ChatKind kind,
    String id,
    bool muted,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final enabledAt = muted ? -1 : DateTime.now().millisecondsSinceEpoch;
    if (!await prefs.setInt('${_key(user, kind, id)}.enabledAt', enabledAt)) {
      throw StateError('Could not save the notification setting');
    }
  }

  Future<void> followEvent(
    String user,
    String id,
    String title,
    int latest,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(user, ChatKind.event, id);
    if (!prefs.containsKey('$key.cursor')) {
      await prefs.setInt('$key.cursor', latest);
    }
    await prefs.setString('$key.title', title);
  }

  void pause() => _session++;

  Future<void> poll(
    String user,
    void Function(String title, String body) fallback,
  ) async {
    if (_busy) return;
    _busy = true;
    final session = _session;
    bool current() => _session == session;
    try {
      if (_userId != user) {
        _userId = user;
        _lastDiscovery = null;
        _communities = {};
        _lastPolled.clear();
      }
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      final now = DateTime.now();
      if (_lastDiscovery == null ||
          now.difference(_lastDiscovery!) >= const Duration(seconds: 30)) {
        _lastDiscovery = now;
        final communities = await _api.listCommunities();
        if (!current()) return;
        _communities = {
          for (final chat in communities)
            if (chat.status == 'active' || chat.isAdmin) chat.id: chat.name,
        };
      }

      final targets = <({ChatKind kind, String id}), String>{
        for (final entry in _communities.entries)
          (kind: ChatKind.community, id: entry.key): entry.value,
      };
      final prefix = 'chat_notifications.$user.event.';
      const suffix = '.title';
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix) && key.endsWith(suffix)) {
          final id = key.substring(prefix.length, key.length - suffix.length);
          targets[(kind: ChatKind.event, id: id)] = prefs.getString(key)!;
        }
      }
      _lastPolled.removeWhere((chat, _) => !targets.containsKey(chat));
      const interval = Duration(seconds: 10);
      final oldest = now.subtract(interval);
      ({ChatKind kind, String id})? next;
      var earliest = oldest;
      for (final chat in targets.keys) {
        final last = _lastPolled[chat];
        if (last == null) {
          next = chat;
          break;
        }
        if (!last.isAfter(earliest)) {
          earliest = last;
          next = chat;
        }
      }
      if (next == null) return;
      _lastPolled[next] = now;
      final key = _key(user, next.kind, next.id);
      final cursor = prefs.getInt('$key.cursor');
      final List<ChatNotice> messages;
      try {
        messages = await _messages(next.kind, next.id, cursor);
      } on ApiException catch (error) {
        if (current() &&
            error.statusCode == 404 &&
            next.kind == ChatKind.event) {
          await prefs.remove('$key.title');
        }
        return;
      }
      if (!current()) return;
      if (cursor == null) {
        await prefs.setInt('$key.cursor', messages.lastOrNull?.seq ?? 0);
        return;
      }
      for (final message in messages) {
        if (!current()) return;
        final enabledAt = prefs.getInt('$key.enabledAt') ?? 0;
        if (message.senderId != user &&
            enabledAt >= 0 &&
            message.sentAt.millisecondsSinceEpoch >= enabledAt) {
          final title = targets[next]!;
          final body = '${message.author}: ${message.body}';
          var shown = false;
          try {
            shown = await CalendarNotificationService.instance
                .showChatMessage(title, body);
          } catch (error) {
            debugPrint('Could not display a chat notification: $error');
          }
          if (!current()) return;
          if (!shown) fallback(title, body);
        }
        await prefs.setInt('$key.cursor', message.seq);
      }
      if (messages.length == 50) _lastPolled[next] = oldest;
    } catch (error) {
      debugPrint('Could not check for chat notifications: $error');
    } finally {
      _busy = false;
    }
  }

  Future<List<ChatNotice>> _messages(
      ChatKind kind, String id, int? cursor) async {
    final limit = cursor == null ? 1 : 50;
    if (kind == ChatKind.community) {
      final page =
          await _api.listCommunityMessages(id, after: cursor, limit: limit);
      return [
        for (final message in page.data)
          (
            seq: message.seq,
            senderId: message.userId,
            author: message.authorName,
            body: message.content,
            sentAt: message.createdAt
          ),
      ];
    }
    final page =
        await _api.listEventMessagesCursor(id, after: cursor, limit: limit);
    return [
      for (final message in page.data)
        (
          seq: message.seq,
          senderId: message.userId,
          author: message.authorName,
          body: message.content,
          sentAt: message.createdAt
        ),
    ];
  }
}
