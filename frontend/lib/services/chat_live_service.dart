import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import 'api_service.dart';

typedef ChatRoom = ({String kind, String id});
typedef ChatChange = ({String? deleted});

String newChatMessageId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

final chatLiveProvider = Provider<ChatLiveService>((ref) {
  final service = ChatLiveService(ref.watch(apiServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});

class ChatLiveService {
  ChatLiveService(this._api);

  final ApiService _api;
  final _rooms = <ChatRoom, StreamController<ChatChange?>>{};
  final _readyRooms = <ChatRoom>{};
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  var _delay = const Duration(seconds: 2);
  var _generation = 0;
  bool _connecting = false;
  bool _disposed = false;

  /// A null signal requests HTTP fallback until the connection is restored.
  Stream<ChatChange?> watch(String kind, String id) {
    final room = (kind: kind, id: id);
    final controller = _rooms.putIfAbsent(room, () {
      late final StreamController<ChatChange?> controller;
      controller = StreamController<ChatChange?>.broadcast(
        onListen: () {
          _send('subscribe', room);
          unawaited(_connect());
        },
        onCancel: () {
          _send('unsubscribe', room);
          _rooms.remove(room);
          _readyRooms.remove(room);
          unawaited(controller.close());
          if (_rooms.isEmpty) _disconnect(retry: false);
        },
      );
      return controller;
    });
    return Stream.multi((listener) {
      final subscription =
          controller.stream.listen(listener.add, onDone: listener.close);
      listener.onCancel = subscription.cancel;
      if (_readyRooms.contains(room)) listener.add((deleted: null));
    });
  }

  void _send(String op, ChatRoom room) {
    _socket?.sink.add(jsonEncode({'op': op, 'kind': room.kind, 'id': room.id}));
  }

  Future<void> _connect() async {
    if (_disposed || _connecting || _socket != null || _rooms.isEmpty) return;
    _connecting = true;
    final generation = _generation;
    WebSocketChannel? socket;
    try {
      final ticket = await _api.createChatLiveTicket();
      if (generation != _generation) return;
      final base = Uri.parse(apiBaseUrl);
      final path = base.path.replaceFirst(RegExp(r'/$'), '');
      socket = WebSocketChannel.connect(
        base.replace(
          scheme: base.scheme == 'https' ? 'wss' : 'ws',
          path: '$path/chat/live',
        ),
        protocols: ['chat.v1', ticket],
      );
      await socket.ready.timeout(const Duration(seconds: 10));
      if (generation != _generation) {
        unawaited(socket.sink.close());
        return;
      }
      _socket = socket;
      _delay = const Duration(seconds: 2);
      _subscription = socket.stream.listen(
        _receive,
        onError: (Object _) => _disconnect(),
        onDone: _disconnect,
      );
      for (final room in _rooms.keys) {
        _send('subscribe', room);
      }
    } catch (_) {
      if (socket != null) unawaited(socket.sink.close());
      if (generation == _generation) _disconnect();
    } finally {
      if (generation == _generation) _connecting = false;
    }
  }

  void _receive(dynamic data) {
    if (data is! String) return;
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) return;
    final kind = decoded['kind'];
    final id = decoded['id'];
    if (kind is! String || id is! String) return;
    final room = (kind: kind, id: id);
    final controller = _rooms[room];
    if (controller == null) return;
    _readyRooms.add(room);
    controller.add((deleted: decoded['deleted'] as String?));
  }

  void _disconnect({bool retry = true}) {
    _generation++;
    _connecting = false;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_socket?.sink.close());
    _subscription = null;
    _socket = null;
    _readyRooms.clear();
    if (_disposed || !retry || _rooms.isEmpty) return;
    for (final controller in _rooms.values) {
      controller.add(null);
    }
    _retry = Timer(_delay, _connect);
    final next = _delay.inSeconds * 2;
    _delay = Duration(seconds: next > 30 ? 30 : next);
  }

  void dispose() {
    _disposed = true;
    _disconnect(retry: false);
    for (final controller in _rooms.values.toList()) {
      unawaited(controller.close());
    }
    _rooms.clear();
  }
}
