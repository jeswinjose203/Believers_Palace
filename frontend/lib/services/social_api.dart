import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import 'api_service.dart';

final socialApiProvider =
    Provider((ref) => SocialApi(ref.watch(apiClientProvider)));

typedef SocialRow = Map<String, dynamic>;
typedef SocialPage = ({List<SocialRow> items, String? cursor, int? before});

class SocialApi {
  SocialApi(this._client);

  final ApiClient _client;

  Future<SocialPage> _page(String path, Map<String, dynamic> query) async {
    final json = await _client.getRaw('/social$path', query: query);
    return (
      items: (json['data'] as List).cast<SocialRow>(),
      cursor: json['nextCursor'] as String?,
      before: json['before'] as int?,
    );
  }

  Future<SocialPage> feed({String? cursor}) =>
      _page('/feed', {if (cursor != null) 'cursor': cursor});

  Future<SocialRow> me() => _client.getRaw('/social/me');

  Future<SocialRow> setUsername(String username) =>
      _client.put('/social/me', (json) => json, body: {'username': username});

  Future<void> post(String body, String clientId, String? attachment) =>
      _client.postVoid('/social/posts', body: {
        'body': body,
        'clientId': clientId,
        if (attachment != null) 'mediaKey': attachment,
      });

  Future<void> setLike(String id, bool liked) async {
    final path = '/social/posts/$id/like';
    if (liked) {
      await _client.put(path, (json) => json);
    } else {
      await _client.delete(path);
    }
  }

  Future<String> upload(PlatformFile file) async {
    final bytes = file.bytes;
    final json = bytes != null
        ? await _client.uploadBytesJson('/social/media',
            bytes: bytes, field: 'file', fileName: file.name)
        : await _client.uploadMultipartJson('/social/media',
            file: File(file.path!), field: 'file', fields: {});
    return json['fileName'] as String;
  }

  Future<List<SocialRow>> people(String username) async =>
      (await _page('/people', {'q': username})).items;

  Future<SocialPage> inbox({String? cursor}) =>
      _page('/threads', {if (cursor != null) 'cursor': cursor});

  Future<String> findThread(String peerId) => _client.get(
      '/social/people/$peerId/thread', (json) => json['id'] as String);

  Future<SocialPage> messages(String threadId, {int? before}) => _page(
      '/threads/$threadId/messages', {if (before != null) 'before': before});

  Future<String> send(String peerId, String body, String clientId) =>
      _client.post('/social/messages', (json) => json['id'] as String,
          body: {'peerId': peerId, 'body': body, 'clientId': clientId});

  Future<void> deleteThread(String id) => _client.delete('/social/threads/$id');
}
