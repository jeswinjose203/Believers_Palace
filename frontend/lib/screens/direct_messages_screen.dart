import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../services/chat_live_service.dart';
import '../services/social_api.dart';
import 'social_post.dart' show SharedPostMessage;

class DirectMessagesScreen extends ConsumerWidget {
  const DirectMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Direct messages'))),
      body: user == null
          ? const SizedBox.shrink()
          : _Inbox(key: ValueKey(user.id), userId: user.id),
    );
  }
}

class _Inbox extends ConsumerStatefulWidget {
  const _Inbox({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<_Inbox> createState() => _InboxState();
}

class _InboxState extends ConsumerState<_Inbox> with WidgetsBindingObserver {
  final _search = TextEditingController();
  List<SocialRow> _threads = [];
  List<SocialRow>? _matches;
  SocialRow? _account;
  String? _cursor;
  String? _error;
  String? _searchError;
  bool _loading = false;
  bool _loaded = false;
  bool _searching = false;
  bool _refreshPending = false;
  int _searchVersion = 0;
  Timer? _poll;
  late final StreamSubscription<ChatChange?> _live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startFallback();
    _live = ref.read(chatLiveProvider).watch('direct', widget.userId).listen(
      (signal) {
        if (signal == null) {
          _startFallback();
        } else {
          _poll?.cancel();
        }
        _load();
      },
    );
  }

  void _startFallback() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _poll?.cancel();
    unawaited(_live.cancel());
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted) return;
    if (_loading) {
      if (!more) _refreshPending = true;
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(socialApiProvider);
      final page = await api.inbox(cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        final existing =
            more ? _threads.map((row) => row['id']).toSet() : <dynamic>{};
        _threads = [
          if (more) ..._threads,
          ...page.items.where((row) => existing.add(row['id'])),
        ];
        _cursor = page.cursor;
        _error = null;
      });
      if (_account == null) {
        final account = await api.me();
        if (mounted) setState(() => _account = account);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loaded = true;
        });
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _find() async {
    final term = _search.text.trim();
    final version = ++_searchVersion;
    setState(() {
      _searching = term.isNotEmpty;
      _matches = null;
      _searchError = null;
    });
    if (term.isEmpty) return;
    try {
      final matches = await ref.read(socialApiProvider).people(term);
      if (mounted && version == _searchVersion) {
        setState(() => _matches = matches);
      }
    } catch (error) {
      if (mounted && version == _searchVersion) {
        setState(() => _searchError = error.toString());
      }
    } finally {
      if (mounted && version == _searchVersion) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _open(SocialRow row, {required bool fromSearch}) async {
    final peerId = row[fromSearch ? 'id' : 'peerId'] as String;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _Conversation(
        userId: widget.userId,
        peerId: peerId,
        name: row['name'] as String,
        username: row['username'] as String,
        threadId: fromSearch ? '' : row['id'] as String,
      ),
    ));
    if (!mounted) return;
    _search.clear();
    _find();
    _load();
  }

  Future<void> _delete(SocialRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Delete this chat for yourself?')),
        content: Text(context.tr('A new message will bring the conversation back.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final id = row['id'] as String;
      await ref.read(socialApiProvider).deleteThread(id);
      if (mounted) {
        setState(() => _threads.removeWhere((row) => row['id'] == id));
        await _load();
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            title: Text(_account == null
                ? context.tr('Your username')
                : '@${_account!['username']}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _search,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _find(),
              onChanged: (_) {
                _searchVersion++;
                setState(() {
                  _matches = null;
                  _searchError = null;
                  _searching = false;
                });
              },
              decoration: InputDecoration(
                labelText: context.tr('Find by username'),
                prefixText: '@',
                suffixIcon: IconButton(
                  tooltip: context.tr('Search'),
                  onPressed: _find,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      );

  Widget _buildResults() {
    if (_searching || !_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError case final error?) {
      return Center(child: Text(error));
    }
    if (_matches case final matches?) {
      if (matches.isEmpty) {
        return Center(child: Text(context.tr('No matching usernames.')));
      }
      return ListView.builder(
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final match = matches[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(match['name'] as String),
            subtitle: Text('@${match['username']}'),
            onTap: () => _open(match, fromSearch: true),
          );
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _threads.length + 1,
        itemBuilder: (context, index) {
          if (index == _threads.length) {
            if (_error != null) {
              return ListTile(
                title: Text(context.tr(_error!)),
                trailing:
                    TextButton(onPressed: _load, child: Text(context.tr('Retry'))),
              );
            }
            if (_threads.isEmpty) {
              return ListTile(
                  title: Text(context.tr('Find someone by username to start a chat.')));
            }
            if (_cursor != null) {
              return TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: Text(context.tr('Load more chats')),
              );
            }
            return const SizedBox.shrink();
          }
          final row = _threads[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(row['name'] as String),
            subtitle: Text(chatMessagePreview(row['preview'] as String),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: PopupMenuButton(
              onSelected: (_) => _delete(row),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'delete', child: Text(context.tr('Delete chat'))),
              ],
            ),
            onTap: () => _open(row, fromSearch: false),
          );
        },
      ),
    );
  }
}

class _Conversation extends ConsumerStatefulWidget {
  const _Conversation({
    required this.userId,
    required this.peerId,
    required this.name,
    required this.username,
    required this.threadId,
  });

  final String userId;
  final String peerId;
  final String name;
  final String username;
  final String threadId;

  @override
  ConsumerState<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends ConsumerState<_Conversation>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  late String _threadId = widget.threadId;
  List<SocialRow> _messages = [];
  int? _before;
  bool _loading = false;
  bool _loaded = false;
  bool _sending = false;
  bool _refreshPending = false;
  bool _reset = false;
  String? _error;
  ({String body, String id})? _retry;
  Timer? _poll;
  late final StreamSubscription<ChatChange?> _live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startFallback();
    _live = ref.read(chatLiveProvider).watch('direct', widget.userId).listen(
      (signal) {
        if (signal == null) {
          _startFallback();
        } else {
          _poll?.cancel();
          if (signal.deleted != null && signal.deleted == _threadId) {
            _reset = true;
          }
        }
        _load();
      },
    );
  }

  void _startFallback() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reset = true;
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _poll?.cancel();
    unawaited(_live.cancel());
    super.dispose();
  }

  Future<void> _load({bool older = false}) async {
    if (!mounted) return;
    if (_loading) {
      if (!older) _refreshPending = true;
      return;
    }
    final reset = _reset;
    _reset = false;
    setState(() => _loading = true);
    try {
      final api = ref.read(socialApiProvider);
      if (_threadId.isEmpty) {
        final id = await api.findThread(widget.peerId);
        if (!mounted) return;
        if (_threadId.isEmpty) _threadId = id;
      }
      if (_threadId.isEmpty) return;
      final page =
          await api.messages(_threadId, before: older ? _before : null);
      if (!mounted) return;
      setState(() {
        final newest = page.items;
        final prior = _messages;
        final keepTail = !reset &&
            newest.isNotEmpty &&
            prior.isNotEmpty &&
            newest.any((row) => row['seq'] == prior.first['seq']);
        final seen = <dynamic>{};
        _messages = [
          if (older) ...prior,
          ...newest,
          if (!older && keepTail) ...prior,
        ].where((row) => seen.add(row['seq'])).toList();
        if (older || !keepTail) _before = page.before;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loaded = true;
        });
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _send() async {
    final draft = _text.text;
    final body = draft.trim();
    if (_sending || body.isEmpty) return;
    final attempt = _retry ??= (body: body, id: newChatMessageId());
    final pending =
        attempt.body == body ? attempt : (body: body, id: newChatMessageId());
    _retry = pending;
    setState(() => _sending = true);
    try {
      final id = await ref.read(socialApiProvider).send(
            widget.peerId,
            pending.body,
            pending.id,
          );
      if (!mounted) return;
      _threadId = id;
      _retry = null;
      if (_text.text == draft) _text.clear();
      await _load();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.name),
              Text('@${widget.username}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_error case final error?)
                ListTile(
                  title: Text(error),
                  trailing:
                      TextButton(onPressed: _load, child: Text(context.tr('Retry'))),
                ),
              Expanded(
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(child: Text(context.tr('Start the conversation.')))
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(12),
                            itemCount:
                                _messages.length + (_before == null ? 0 : 1),
                            itemBuilder: (context, index) {
                              if (index == _messages.length) {
                                return TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () => _load(older: true),
                                  child: Text(context.tr('Load earlier messages')),
                                );
                              }
                              return _bubble(context, _messages[index]);
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        maxLength: 4000,
                        maxLines: 5,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: context.tr('Message'),
                          counterText: '',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Send message'),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _bubble(BuildContext context, SocialRow message) {
    final mine = message['senderId'] == widget.userId;
    final colors = Theme.of(context).colorScheme;
    final sent = DateTime.parse(message['createdAt'] as String).toLocal();
    return Align(
      key: ValueKey(message['seq']),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        child: Card(
          color: mine ? colors.primaryContainer : colors.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SharedPostMessage(message['body'] as String),
                Text(DateFormat.MMMd(context.dateLocale).add_jm().format(sent),
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString())),
  );
}
