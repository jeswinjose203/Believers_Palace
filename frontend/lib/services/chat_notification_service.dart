import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import 'api_service.dart';
import 'calendar_notification_service.dart';
import 'chat_live_service.dart';

enum ChatKind { community, event }

typedef ChatNotice = ({
  int seq,
  String? senderId,
  String author,
  String body,
  DateTime sentAt,
});

final chatNotificationServiceProvider = Provider<ChatNotificationService>(
  (ref) {
    final service = ChatNotificationService(
      ref.watch(apiServiceProvider),
      live: ref.watch(chatLiveProvider),
    );
    ref.onDispose(service.pause);
    return service;
  },
);

typedef CommunityChatPreview = ({
  String author,
  String text,
  DateTime time,
  int unread,
  bool muted,
});

class ChatNotificationService {
  ChatNotificationService(this._api, {ChatLiveService? live}) : _live = live;

  final ApiService _api;
  final ChatLiveService? _live;
  final Map<({ChatKind kind, String id}), DateTime> _lastPolled = {};
  final _subscriptions =
      <({ChatKind kind, String id}), StreamSubscription<ChatChange?>>{};
  final _liveRooms = <({ChatKind kind, String id})>{};
  final _dirtyRooms = <({ChatKind kind, String id})>{};
  final previews = ValueNotifier<Map<String, CommunityChatPreview>>({});
  final preferenceChanges = ValueNotifier<int>(0);
  DateTime? _lastDiscovery;
  Map<String, String> _communities = {};
  String? _userId;
  bool _busy = false;
  int _session = 0;
  int _preferenceWrites = 0;

  String _key(String user, ChatKind kind, String id) =>
      'chat_notifications.$user.${kind.name}.$id';

  Future<bool> muted(String user, ChatKind kind, String id,
      {bool refresh = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (refresh) await _syncPreferences(user, prefs);
    return prefs.getInt('${_key(user, kind, id)}.enabledAt') == -1;
  }

  Future<void> setMuted(
    String user,
    ChatKind kind,
    String id,
    bool muted,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    _preferenceWrites++;
    await _api.setChatPreference(kind.name, id, muted: muted);
    _preferenceWrites++;
    final enabledAt = muted ? -1 : DateTime.now().millisecondsSinceEpoch;
    if (!await prefs.setInt('${_key(user, kind, id)}.enabledAt', enabledAt)) {
      throw StateError('Could not save the notification setting');
    }
    preferenceChanges.value++;
    if (kind == ChatKind.community && _userId == user) {
      final current = previews.value[id];
      if (current != null) {
        previews.value = {
          ...previews.value,
          id: (
            author: current.author,
            text: current.text,
            time: current.time,
            unread: current.unread,
            muted: muted
          ),
        };
      }
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
    if (!prefs.containsKey('$key.followed')) {
      final savedMute = prefs.getInt('$key.enabledAt') == -1;
      await _api.setChatPreference('event', id,
          muted: savedMute ? true : null, onlyIfMissing: true);
      await prefs.setBool('$key.followed', true);
    }
  }

  Future<void> _syncPreferences(String user, SharedPreferences prefs) async {
    final session = _session;
    final writes = _preferenceWrites;
    try {
      final remote = await _api.listChatPreferences();
      if (session != _session || writes != _preferenceWrites) return;
      var changed = false;
      for (final entry in remote.entries) {
        if (session != _session || writes != _preferenceWrites) return;
        final key = 'chat_notifications.$user.${entry.key}.enabledAt';
        final local = prefs.getInt(key);
        if (entry.value != (local == -1)) {
          await prefs.setInt(
              key, entry.value ? -1 : DateTime.now().millisecondsSinceEpoch);
          changed = true;
        }
      }
      if (changed) preferenceChanges.value++;
      final prefix = 'chat_notifications.$user.';
      const suffix = '.enabledAt';
      for (final id in _communities.keys) {
        final room = 'community.$id';
        if (remote.containsKey(room) ||
            prefs.getInt('$prefix$room$suffix') != -1) {
          continue;
        }
        if (session != _session || writes != _preferenceWrites) return;
        await _api.setChatPreference('community', id,
            muted: true, onlyIfMissing: true);
      }
    } catch (error) {
      debugPrint('Could not synchronize chat preferences: $error');
    }
  }

  void markCommunityRead(String user, String id) {
    if (_userId != user) return;
    final old = previews.value[id];
    if (old == null || old.unread == 0) return;
    previews.value = {
      ...previews.value,
      id: (
        author: old.author,
        text: old.text,
        time: old.time,
        unread: 0,
        muted: old.muted
      ),
    };
  }

  CommunityChatPreview? communityPreview(String? user, String id) =>
      user == _userId ? previews.value[id] : null;

  void pause() {
    _session++;
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _liveRooms.clear();
    _dirtyRooms.clear();
  }

  void _watchTargets(Set<({ChatKind kind, String id})> targets) {
    final live = _live;
    if (live == null) return;
    for (final room in _subscriptions.keys.toList()) {
      if (targets.contains(room)) continue;
      unawaited(_subscriptions.remove(room)?.cancel());
      _liveRooms.remove(room);
      _dirtyRooms.remove(room);
    }
    for (final room in targets) {
      _subscriptions.putIfAbsent(room, () {
        return live.watch(room.kind.name, room.id).listen((change) {
          if (change == null) {
            _liveRooms.remove(room);
          } else {
            _liveRooms.add(room);
            _dirtyRooms.add(room);
          }
        });
      });
    }
  }

  Future<void> poll(
    String user,
    void Function(String title, String body) fallback, {
    DateTime? notifySince,
  }) async {
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
        previews.value = {};
      }
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return;
      final now = DateTime.now();
      if (_lastDiscovery == null ||
          now.difference(_lastDiscovery!) >= const Duration(seconds: 30)) {
        _lastDiscovery = now;
        final communities = await _api.listJoinedCommunityChats();
        if (!current()) return;
        _communities = communities;
        await _syncPreferences(user, prefs);
        if (!current()) return;
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
      _watchTargets(targets.keys.toSet());
      const interval = Duration(seconds: 10);
      final oldest = now.subtract(interval);
      ({ChatKind kind, String id})? next;
      var earliest = oldest;
      for (final chat in targets.keys) {
        final last = _lastPolled[chat];
        final dirty = _dirtyRooms.contains(chat);
        if (_liveRooms.contains(chat) && !dirty) continue;
        if (last == null) {
          next = chat;
          break;
        }
        if ((dirty && next == null) || !last.isAfter(earliest)) {
          earliest = last;
          next = chat;
        }
      }
      if (next == null) return;
      _dirtyRooms.remove(next);
      _lastPolled[next] = now;
      final key = _key(user, next.kind, next.id);
      final cursor = prefs.getInt('$key.cursor');
      final List<ChatNotice> messages;
      try {
        messages = await _messages(next.kind, next.id, cursor);
      } on ApiException catch (error) {
        _liveRooms.remove(next);
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
        if (current() && next.kind == ChatKind.community) {
          _preview(next.id, messages,
              newMessages: 0, muted: prefs.getInt('$key.enabledAt') == -1);
        }
        return;
      }
      if (next.kind == ChatKind.community) {
        final previewMessages =
            messages.isEmpty && previews.value[next.id] == null
                ? await _messages(next.kind, next.id, null)
                : messages;
        if (!current()) return;
        _preview(next.id, previewMessages,
            newMessages:
                messages.where((message) => message.senderId != user).length,
            muted: prefs.getInt('$key.enabledAt') == -1);
      }
      for (final message in messages) {
        if (!current()) return;
        final enabledAt = prefs.getInt('$key.enabledAt') ?? 0;
        if (message.senderId != user &&
            (notifySince == null || !message.sentAt.isBefore(notifySince)) &&
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
      if (messages.length == 50) {
        _lastPolled[next] = oldest;
        if (_liveRooms.contains(next)) _dirtyRooms.add(next);
      }
    } catch (error) {
      debugPrint('Could not check for chat notifications: $error');
    } finally {
      _busy = false;
    }
  }

  void _preview(String id, List<ChatNotice> messages,
      {required int newMessages, required bool muted}) {
    if (messages.isEmpty) return;
    final latest = messages.last;
    previews.value = {
      ...previews.value,
      id: (
        author: latest.author,
        text: latest.body,
        time: latest.sentAt,
        unread: (previews.value[id]?.unread ?? 0) + newMessages,
        muted: muted,
      ),
    };
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
