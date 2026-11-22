import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../core/auth_provider.dart';
import '../services/chat_live_service.dart';
import '../services/social_api.dart';
import 'direct_messages_screen.dart';
import 'signup_screen.dart';
import 'verify_email_screen.dart';

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
      final page = await ref.read(socialApiProvider).feed(
            cursor: more ? _cursor : null,
          );
      if (mounted) {
        setState(() {
          _posts = more ? [..._posts, ...page.items] : page.items;
          _cursor = page.cursor;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _started = true;
          _busy = false;
        });
      }
    }
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
            }
          }
        });
      }
    } catch (error) {
      if (mounted) showSocialError(context, error);
    } finally {
      if (mounted) setState(() => _reacting.remove(id));
    }
  }

  Future<void> _compose() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    if (!user.emailVerified || !user.phoneVerified) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Verify your account to post'),
          content: Text(
            'Email ${user.emailVerified ? 'verified' : 'unverified'}\n'
            'Phone ${user.phoneVerified ? 'verified' : 'unverified'}',
          ),
          actions: [
            if (!user.emailVerified)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const VerifyEmailScreen(),
                  ));
                },
                child: const Text('Verify email'),
              ),
            if (!user.phoneVerified)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        const SignupScreen(verifyingExistingAccount: true),
                  ));
                },
                child: const Text('Verify phone'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _ComposeScreen()),
    );
    if (posted == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Feed'),
          actions: [
            IconButton(
              tooltip: 'Direct messages',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const DirectMessagesScreen(),
              )),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _compose,
          icon: const Icon(Icons.add),
          label: const Text('Post'),
        ),
        body: !_started
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: _posts.length + 1,
                  itemBuilder: (context, index) {
                    if (index < _posts.length) {
                      final post = _posts[index];
                      return _PostCard(
                        key: ValueKey(post['id']),
                        post: post,
                        react: _reacting.contains(post['id'])
                            ? null
                            : () => _react(post),
                      );
                    }
                    if (_error != null) {
                      return ListTile(
                        title: Text(_error!),
                        trailing: TextButton(
                          onPressed:
                              _busy ? null : () => _load(more: _cursor != null),
                          child: const Text('Retry'),
                        ),
                      );
                    }
                    if (_posts.isEmpty) {
                      return const ListTile(title: Text('No posts yet.'));
                    }
                    if (_cursor != null) {
                      return TextButton(
                        onPressed: _busy ? null : () => _load(more: true),
                        child: Text(_busy ? 'Loading…' : 'Load more'),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
      );
}

void showSocialError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString())),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({super.key, required this.post, required this.react});

  final SocialRow post;
  final VoidCallback? react;

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
    final body = post['body'] as String;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(post['name'] as String),
            subtitle: Text(
                '@${post['username']} · ${DateFormat.MMMd().add_jm().format(DateTime.parse(post['createdAt'] as String).toLocal())}'),
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
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('Image unavailable'),
                ),
              ),
            ),
          if (url != null && video)
            ListTile(
              leading: const Icon(Icons.play_circle_outline, size: 32),
              title: const Text('Play video'),
              onTap: () async {
                try {
                  if (!await launchUrl(url) && context.mounted) {
                    showSocialError(context, 'Could not open video.');
                  }
                } catch (error) {
                  if (context.mounted) showSocialError(context, error);
                }
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: react,
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
              label: Text(likes > 200 ? '200+ likes' : '$likes likes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeScreen extends ConsumerStatefulWidget {
  const _ComposeScreen();

  @override
  ConsumerState<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<_ComposeScreen> {
  final _text = TextEditingController();
  final _clientId = newChatMessageId();
  PlatformFile? _file;
  String? _uploaded;
  bool _busy = false;

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
        showSocialError(context, 'Attachments can be up to 25 MB.');
        return;
      }
      setState(() {
        _uploaded = null;
        _file = file;
      });
    } catch (error) {
      if (mounted) showSocialError(context, error);
    }
  }

  Future<void> _publish() async {
    if (_busy) return;
    final body = _text.text.trim();
    if (body.isEmpty && _file == null) {
      showSocialError(context, 'Write something or attach an image or video.');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(socialApiProvider);
      final file = _file;
      if (file != null) _uploaded ??= await api.upload(file);
      await api.post(body, _clientId, _uploaded);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showSocialError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('New post'),
          actions: [
            TextButton(
              onPressed: _busy ? null : _publish,
              child: Text(_busy ? 'Posting…' : 'Publish'),
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
                  const InputDecoration(hintText: 'What’s on your mind?'),
            ),
            if (_file case final file?)
              ListTile(
                title: Text(file.name),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _file = null;
                            _uploaded = null;
                          }),
                  icon: const Icon(Icons.close),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Attach photo or video'),
            ),
          ],
        ),
      );
}
