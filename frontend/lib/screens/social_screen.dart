import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import 'social_post.dart';
import '../core/auth_provider.dart';
import '../services/chat_live_service.dart';
import '../services/social_api.dart';
import '../widgets/user_error.dart';
import 'direct_messages_screen.dart';
import 'signup_screen.dart';

class SocialScreen extends ConsumerStatefulWidget {
  const SocialScreen({super.key});

  @override
  ConsumerState<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends ConsumerState<SocialScreen> {
  List<SocialRow> _posts = [];
  final _reacting = <String>{};
  String? _cursor;
  bool _busy = false;
  bool _started = false;
  bool _mine = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(socialApiProvider);
      final cursor = more ? _cursor : null;
      final page = await (_mine
          ? api.myPosts(cursor: cursor)
          : api.feed(cursor: cursor));
      if (mounted) {
        setState(() {
          _posts = more ? [..._posts, ...page.items] : page.items;
          _cursor = page.cursor;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        final message = userErrorMessage(error,
            fallback: 'Could not load posts. Please try again.');
        setState(() => _error = message);
        if (_posts.isNotEmpty && ModalRoute.of(context)?.isCurrent == true) {
          showUserError(context, message);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _started = true;
          _busy = false;
        });
      }
    }
  }

  void _selectFeed(bool mine) {
    if (_busy || _deleting || _mine == mine) return;
    setState(() {
      _mine = mine;
      _posts = [];
      _cursor = null;
      _error = null;
      _started = false;
    });
    _load();
  }

  Future<void> _delete(SocialRow post) async {
    if (_deleting || _busy) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Delete post?')),
          content:
              Text(context.tr('Your post and its comments will be removed.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(socialApiProvider).deletePost(post['id'] as String);
      if (mounted) {
        setState(() => _posts.removeWhere((item) => item['id'] == post['id']));
        await _load();
      }
    } catch (error) {
      if (mounted) {
        showUserError(context, error,
            fallback: 'Could not delete your post. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _edit(SocialRow post) async {
    final changes = await Navigator.of(context).push<SocialRow>(
      MaterialPageRoute(builder: (_) => _ComposeScreen(post: post)),
    );
    if (!mounted || changes == null) return;
    setState(() {
      for (final item in _posts.where((item) => item['id'] == post['id'])) {
        item.addAll(changes);
      }
    });
  }

  Future<void> _react(SocialRow post) async {
    final id = post['id'] as String;
    if (!_reacting.add(id)) return;
    final liked = post['liked'] as bool;
    setState(() {});
    try {
      await ref.read(socialApiProvider).setLike(id, !liked);
      if (mounted) {
        setState(() {
          for (final current in _posts.where((entry) => entry['id'] == id)) {
            if (current['liked'] == liked) {
              current['liked'] = !liked;
              current['likes'] = (current['likes'] as int) + (liked ? -1 : 1);
              if (liked) current.remove('recentLiker');
            }
          }
        });
      }
    } catch (error) {
      if (mounted) {
        showUserError(context, error,
            fallback: 'Could not update your like. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _reacting.remove(id));
    }
  }

  Future<void> _compose() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    if (!user.phoneVerified) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.tr('Verify your phone number to post.')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const SignupScreen(verifyingExistingAccount: true),
                ));
              },
              child: Text(dialogContext.tr('Verify phone')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.tr('Close')),
            ),
          ],
        ),
      );
      return;
    }
    final posted = await Navigator.of(context).push<SocialRow>(
      MaterialPageRoute(builder: (_) => const _ComposeScreen()),
    );
    if (posted != null && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Feed')),
          actions: [
            IconButton(
              tooltip: context.tr('Direct messages'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DirectMessagesScreen(),
              )),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy || _deleting ? null : _compose,
          icon: const Icon(Icons.add),
          label: Text(context.tr('Post')),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(context.tr('Feed'))),
                  ButtonSegment(
                      value: true, label: Text(context.tr('My Posts'))),
                ],
                selected: {_mine},
                onSelectionChanged: _busy || _deleting
                    ? null
                    : (value) => _selectFeed(value.single),
              ),
            ),
            Expanded(
                child: !_started
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: () async {
                          if (!_deleting) await _load();
                        },
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: _posts.length + 1,
                          itemBuilder: (context, index) {
                            if (index < _posts.length) {
                              final post = _posts[index];
                              return SocialPostCard(
                                key: ValueKey(post['id']),
                                post: post,
                                actions: _mine
                                    ? PopupMenuButton<String>(
                                        tooltip: context.tr('Post options'),
                                        enabled: !_busy && !_deleting,
                                        onSelected: (action) {
                                          if (action == 'edit') {
                                            _edit(post);
                                          } else {
                                            _delete(post);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                              value: 'edit',
                                              child: Text(
                                                  context.tr('Edit post'))),
                                          PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                  context.tr('Delete post'))),
                                        ],
                                      )
                                    : null,
                                onComment: () {
                                  if (!mounted) return;
                                  setState(() {
                                    for (final current in _posts.where(
                                        (entry) => entry['id'] == post['id'])) {
                                      current['comments'] =
                                          (current['comments'] as int? ?? 0) +
                                              1;
                                    }
                                  });
                                },
                                react: _reacting.contains(post['id'])
                                    ? null
                                    : () => _react(post),
                              );
                            }
                            if (_error != null) {
                              return ListTile(
                                title: Text(context.tr(_error!)),
                                trailing: TextButton(
                                  onPressed:
                                      _busy || _deleting ? null : () => _load(),
                                  child: Text(context.tr('Retry')),
                                ),
                              );
                            }
                            if (_cursor != null) {
                              return TextButton(
                                onPressed: _busy || _deleting
                                    ? null
                                    : () => _load(more: true),
                                child: Text(_busy
                                    ? context.tr('Loading…')
                                    : context.tr('Load more')),
                              );
                            }
                            if (_posts.isEmpty) {
                              return ListTile(
                                  title: Text(context.tr(_mine
                                      ? 'You haven’t posted yet.'
                                      : 'No posts yet.')));
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      )),
          ],
        ),
      );
}

class _ComposeScreen extends ConsumerStatefulWidget {
  const _ComposeScreen({this.post});

  final SocialRow? post;

  @override
  ConsumerState<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<_ComposeScreen> {
  final _text = TextEditingController();
  final _clientId = newChatMessageId();
  PlatformFile? _file;
  String? _uploaded;
  String? _existingMedia;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.text = widget.post?['body'] as String? ?? '';
    _existingMedia = widget.post?['mediaKey'] as String?;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'webm'],
        withData: kIsWeb,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 25 * 1024 * 1024) {
        showUserError(context, 'Attachments can be up to 25 MB.');
        return;
      }
      setState(() {
        _uploaded = null;
        _existingMedia = null;
        _file = file;
      });
    } catch (error) {
      if (mounted) {
        showUserError(context, error,
            fallback: 'Could not open your files. Please try again.');
      }
    }
  }

  Future<void> _publish() async {
    if (_busy) return;
    final body = _text.text.trim();
    if (body.isEmpty && _file == null && _existingMedia == null) {
      showUserError(context, 'Write something or attach an image or video.');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(socialApiProvider);
      final file = _file;
      if (file != null) _uploaded ??= await api.upload(file);
      final media = _uploaded ?? _existingMedia;
      final id = widget.post?['id'] as String?;
      final SocialRow changes;
      if (id == null) {
        await api.post(body, _clientId, media);
        changes = {};
      } else {
        changes = await api.editPost(id, body, media);
      }
      if (mounted) Navigator.pop(context, changes);
    } catch (error) {
      if (mounted) {
        showUserError(context, error,
            fallback: widget.post == null
                ? 'Could not publish your post. Please try again.'
                : 'Could not save your post. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title:
              Text(context.tr(widget.post == null ? 'New post' : 'Edit post')),
          actions: [
            TextButton(
              onPressed: _busy ? null : _publish,
              child: Text(context.tr(widget.post == null ? 'Publish' : 'Save')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _text,
              enabled: !_busy,
              maxLength: 4000,
              minLines: 4,
              maxLines: 12,
              decoration:
                  InputDecoration(hintText: context.tr('What’s on your mind?')),
            ),
            if (_file != null || _existingMedia != null)
              ListTile(
                title: Text(_file?.name ?? context.tr('Current attachment')),
                trailing: IconButton(
                  tooltip: context.tr('Remove attachment'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _file = null;
                            _uploaded = null;
                            _existingMedia = null;
                          }),
                  icon: const Icon(Icons.close),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(context.tr('Attach photo or video')),
            ),
          ],
        ),
      );
}
