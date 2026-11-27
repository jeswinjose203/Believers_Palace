import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_locale.dart';
import '../config.dart';
import '../core/auth_provider.dart';
import '../services/api_service.dart';
import '../services/chat_live_service.dart';
import '../services/social_api.dart';

class SocialPostCard extends StatelessWidget {
  const SocialPostCard(
      {super.key, required this.post, required this.react, this.onComment});

  final SocialRow post;
  final VoidCallback? react;
  final VoidCallback? onComment;

  @override
  Widget build(BuildContext context) {
    final key = post['mediaKey'] as String?;
    final url = key == null
        ? null
        : Uri.parse(post['mediaUrl'] as String? ?? '$apiBaseUrl/media/$key');
    final video =
        key?.endsWith('.mp4') == true || key?.endsWith('.webm') == true;
    final liked = post['liked'] as bool;
    final likes = post['likes'] as int;
    final comments = post['comments'] as int? ?? 0;
    final recent = post['recentLiker'] as String?;
    final id = post['id'] as String;
    final body = post['body'] as String;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(post['name'] as String),
            subtitle: Text(
                '@${post['username']} · ${DateFormat.MMMd(context.dateLocale).add_jm().format(DateTime.parse(post['createdAt'] as String).toLocal())}'),
          ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText(body),
            ),
          if (url != null && !video)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: Image.network(
                url.toString(),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(context.tr('Image unavailable')),
                ),
              ),
            ),
          if (url != null && video)
            ListTile(
              leading: const Icon(Icons.play_circle_outline, size: 32),
              title: Text(context.tr('Play video')),
              onTap: () async {
                try {
                  if (!await launchUrl(url) && context.mounted) {
                    _showError(context, 'Could not open video.');
                  }
                } catch (error) {
                  if (context.mounted) _showError(context, error);
                }
              },
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: liked ? context.tr('Unlike') : context.tr('Like'),
                onPressed: react,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Theme.of(context).colorScheme.error : null),
              ),
              TextButton(
                onPressed: likes == 0
                    ? null
                    : () => _showEngagement(context, id, likes: true),
                child: Text(context.tr(likes == 1 ? '{0} like' : '{0} likes', [likes])),
              ),
              TextButton.icon(
                onPressed: () =>
                    _showEngagement(context, id, onComment: onComment),
                icon: const Icon(Icons.mode_comment_outlined),
                label:
                    Text(context.tr(comments == 1 ? '{0} comment' : '{0} comments', [comments])),
              ),
              IconButton(
                tooltip: context.tr('Share post'),
                onPressed: () => _showShare(context, id),
                icon: const Icon(Icons.send_outlined),
              ),
            ],
          ),
          if (recent != null && likes > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(context.tr(likes > 1 ? 'Liked by @{0} and others' : 'Liked by @{0}', [recent])),
            ),
        ],
      ),
    );
  }
}

Future<void> _showEngagement(BuildContext context, String id,
        {bool likes = false, VoidCallback? onComment}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) =>
          _EngagementSheet(id: id, likes: likes, onComment: onComment),
    );

class _EngagementSheet extends ConsumerStatefulWidget {
  const _EngagementSheet(
      {required this.id, required this.likes, this.onComment});

  final String id;
  final bool likes;
  final VoidCallback? onComment;

  @override
  ConsumerState<_EngagementSheet> createState() => _EngagementSheetState();
}

class _EngagementSheetState extends ConsumerState<_EngagementSheet> {
  final _input = TextEditingController();
  final _rows = <SocialRow>[];
  String? _cursor;
  String? _error;
  ({String body, String id})? _draft;
  bool _loading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(socialApiProvider)
          .engagement(widget.id, likes: widget.likes, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        _rows.addAll(page.items);
        _cursor = page.cursor;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _loading || _error != null) return;
    final body = _input.text.trim();
    if (body.isEmpty) return;
    final draft =
        _draft?.body == body ? _draft! : (body: body, id: newChatMessageId());
    _draft = draft;
    final onComment = widget.onComment;
    setState(() => _sending = true);
    try {
      final entry = await ref
          .read(socialApiProvider)
          .comment(widget.id, draft.body, draft.id);
      if (!mounted) {
        onComment?.call();
        return;
      }
      if (!_rows.any((row) => row['id'] == entry['id'])) {
        setState(() => _rows.insert(0, entry));
        onComment?.call();
      }
      _input.clear();
      _draft = null;
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canComment = ref.watch(authProvider).user?.emailVerified == true;
    return _sheet(
      context,
      title: widget.likes ? context.tr('Likes') : context.tr('Comments'),
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length + 1,
            itemBuilder: (_, index) {
              if (index < _rows.length) {
                final row = _rows[index];
                return ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text('@${row['username']}'),
                  subtitle: widget.likes
                      ? null
                      : SelectableText(row['body'] as String),
                );
              }
              if (_loading) return const LinearProgressIndicator();
              if (_error != null) {
                return ListTile(
                  title: Text(context.tr(_error!)),
                  trailing:
                      TextButton(onPressed: _load, child: Text(context.tr('Retry'))),
                );
              }
              if (_cursor != null) {
                return TextButton(
                  onPressed: _sending ? null : _load,
                  child: Text(context.tr('Load more')),
                );
              }
              if (_rows.isEmpty) {
                return ListTile(
                    title: Text(
                        widget.likes ? context.tr('No likes yet.') : context.tr('No comments yet.')));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        if (!widget.likes)
          if (canComment)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _input,
                enabled: !_sending,
                textInputAction: TextInputAction.send,
                maxLength: 1000,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  labelText: context.tr('Add a comment'),
                  suffixIcon: IconButton(
                    tooltip: context.tr('Post comment'),
                    onPressed:
                        _sending || _loading || _error != null ? null : _send,
                    icon: const Icon(Icons.send_outlined),
                  ),
                ),
              ),
            )
          else
            ListTile(title: Text(context.tr('Verify your email to comment.'))),
      ],
    );
  }
}

class SharedPostMessage extends StatelessWidget {
  const SharedPostMessage(this.message, {super.key, this.selectable = true});

  final String message;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final id = sharedPostId(message);
    if (id == null) return selectable ? SelectableText(message) : Text(message);
    return TextButton.icon(
      icon: const Icon(Icons.article_outlined),
      label: Text(context.tr('View shared post')),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _SharedPostScreen(id)),
      ),
    );
  }
}

class _SharedPostScreen extends ConsumerStatefulWidget {
  const _SharedPostScreen(this.id);

  final String id;

  @override
  ConsumerState<_SharedPostScreen> createState() => _SharedPostScreenState();
}

class _SharedPostScreenState extends ConsumerState<_SharedPostScreen> {
  late Future<SocialRow> _post;
  bool _reacting = false;

  @override
  void initState() {
    super.initState();
    _post = ref.read(socialApiProvider).getPost(widget.id);
  }

  void _reload() {
    setState(() => _post = ref.read(socialApiProvider).getPost(widget.id));
  }

  Future<void> _react(SocialRow post) async {
    if (_reacting) return;
    setState(() => _reacting = true);
    try {
      final api = ref.read(socialApiProvider);
      await api.setLike(widget.id, post['liked'] != true);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Shared post'))),
        body: FutureBuilder<SocialRow>(
          future: _post,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListTile(
                title: Text(context.tr('Could not open this post.')),
                trailing:
                    TextButton(onPressed: _reload, child: Text(context.tr('Retry'))),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SocialPostCard(
                  post: snapshot.data!,
                  react: _reacting ? null : () => _react(snapshot.data!),
                  onComment: _reload,
                ),
              ],
            );
          },
        ),
      );
}

Future<void> _showShare(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ShareSheet(id),
    );

typedef _Destination = ({String id, String name, String? username});

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet(this.postId);

  final String postId;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _search = TextEditingController();
  final _targets = <_Destination>[];
  final _sent = <(bool, String)>{};
  final _attempts = <(bool, String), String>{};
  String? _cursor;
  String? _error;
  String _query = '';
  bool _groups = false;
  bool _loading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(authProvider).user?.emailVerified == true) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      if (reset) {
        _cursor = null;
        _targets.clear();
      }
      _loading = true;
      _error = null;
    });
    try {
      final social = ref.read(socialApiProvider);
      List<_Destination> targets;
      String? next;
      if (_groups) {
        final page = await ref
            .read(apiServiceProvider)
            .listCommunityPage(joined: true, cursor: _cursor);
        next = page.nextCursor;
        targets = [
          for (final group in page.items)
            (id: group.id, name: group.name, username: null),
        ];
      } else {
        final page =
            _query.isEmpty ? await social.inbox(cursor: _cursor) : null;
        next = page?.cursor;
        final rows = page?.items ?? await social.people(_query);
        targets = [
          for (final row in rows)
            (
              id: (row['peerId'] ?? row['id']) as String,
              name: row['name'] as String,
              username: row['username'] as String
            ),
        ];
      }
      if (mounted) {
        setState(() {
          final existing = _targets.map((target) => target.id).toSet();
          _targets.addAll(targets.where((target) => existing.add(target.id)));
          _cursor = next;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(_Destination target) async {
    final key = (_groups, target.id);
    if (_sending || _sent.contains(key)) return;
    setState(() => _sending = true);
    final clientId = _attempts.putIfAbsent(key, newChatMessageId);
    final body = sharedPostReference(widget.postId);
    try {
      if (_groups) {
        await ref
            .read(apiServiceProvider)
            .postCommunityMessage(target.id, body, clientId: clientId);
      } else {
        await ref.read(socialApiProvider).send(target.id, body, clientId);
      }
      if (mounted) setState(() => _sent.add(key));
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).user?.emailVerified != true) {
      return ListTile(
          title: Text(context.tr('Verify your email to share posts in chats.')));
    }
    return _sheet(
      context,
      title: context.tr('Share post'),
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(context.tr('Chats'))),
            ButtonSegment(value: true, label: Text(context.tr('Groups'))),
          ],
          selected: {_groups},
          onSelectionChanged: _loading || _sending
              ? null
              : (selection) {
                  if (_groups == selection.single) return;
                  setState(() {
                    _groups = selection.single;
                    _query = '';
                    _search.clear();
                  });
                  _load(reset: true);
                },
        ),
        if (!_groups)
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              enabled: !_loading && !_sending,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _find(),
              decoration: InputDecoration(
                labelText: context.tr('Find by username'),
                suffixIcon: IconButton(
                  tooltip: context.tr('Search'),
                  onPressed: _loading || _sending ? null : _find,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _targets.length + 1,
            itemBuilder: (_, index) {
              if (index < _targets.length) {
                final target = _targets[index];
                final sent = _sent.contains((_groups, target.id));
                return ListTile(
                  title: Text(target.name),
                  subtitle: target.username == null
                      ? null
                      : Text('@${target.username}'),
                  trailing: FilledButton.tonal(
                    onPressed: sent || _sending ? null : () => _send(target),
                    child: Text(sent ? context.tr('Sent') : context.tr('Send')),
                  ),
                );
              }
              if (_loading) return const LinearProgressIndicator();
              if (_error != null) {
                return ListTile(
                    title: Text(context.tr(_error!)),
                    trailing: TextButton(
                        onPressed: _sending ? null : _load,
                        child: Text(context.tr('Retry'))));
              }
              if (_cursor != null) {
                return TextButton(
                    onPressed: _sending ? null : _load,
                    child: Text(context.tr('Load more')));
              }
              if (_targets.isEmpty) {
                return ListTile(
                    title: Text(_groups
                        ? context.tr('No group chats found.')
                        : _query.isEmpty
                            ? context.tr('Search for someone by username.')
                            : context.tr('No matching usernames.')));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  void _find() {
    if (_loading || _sending) return;
    _query = _search.text.trim();
    _load(reset: true);
  }
}

Widget _sheet(BuildContext context,
        {required String title, required List<Widget> children}) =>
    Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .78,
        child: Column(
          children: [
            ListTile(
              title: Text(title, style: Theme.of(context).textTheme.titleLarge),
              trailing: IconButton(
                tooltip: context.tr('Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(context.tr(error.toString()))));
}
