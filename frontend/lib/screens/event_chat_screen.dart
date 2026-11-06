import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Per-event chat. If the event requires registration, only registered users
/// (and church staff) can read and post; otherwise any signed-in user can.
/// A message can be deleted by its author or by a church admin / super admin.
///
/// Loading uses a cursor (`seq`) instead of fixed pages:
///  * open  -> the latest 50 messages
///  * poll  -> only messages newer than the newest one we have
///  * scroll to the top -> the next 50 older messages
/// Polling pauses while the app is in the background and backs off on errors.
class EventChatScreen extends ConsumerStatefulWidget {
  final Event event;

  const EventChatScreen({super.key, required this.event});

  @override
  ConsumerState<EventChatScreen> createState() => _EventChatScreenState();
}

/// A message that has been typed but not yet confirmed by the server.
class _Pending {
  final int localId;
  final String content;
  bool failed = false;

  _Pending(this.localId, this.content);
}

class _EventChatScreenState extends ConsumerState<EventChatScreen>
    with WidgetsBindingObserver {
  static const _pageSize = 50;
  static const _pollInterval = Duration(seconds: 3);
  static const _maxBackoff = Duration(seconds: 30);

  final _input = TextEditingController();
  final _scroll = ScrollController();

  // Oldest first, unique by id, sorted by seq.
  List<ChatMessage> _messages = [];
  final List<_Pending> _pending = [];
  final Set<String> _fresh = {}; // ids that arrived live (animate in)

  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMoreOlder = false;
  bool _notRegistered = false;
  bool _offline = false;
  String? _error;
  int _unseen = 0;
  int _failures = 0;
  int _nextLocalId = 0;

  bool _polling = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _loadLatest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollNow();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  // ---- loading -----------------------------------------------------------

  ApiService get _api => ref.read(apiServiceProvider);

  bool get _atBottom => !_scroll.hasClients || _scroll.position.pixels <= 40;

  Future<void> _loadLatest() async {
    try {
      final page = await _api.listEventMessagesCursor(widget.event.id,
          limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _messages = page.data;
        _hasMoreOlder = page.hasMore;
        _loading = false;
        _error = null;
        _offline = false;
        _failures = 0;
      });
      _scheduleNext();
    } catch (e) {
      if (!mounted) return;
      if (_handleNotRegistered(e)) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      _failures++;
      _scheduleNext();
    }
  }

  bool _handleNotRegistered(Object e) {
    if (e is ApiException && e.code == 'not_registered') {
      _timer?.cancel();
      setState(() {
        _loading = false;
        _notRegistered = true;
      });
      return true;
    }
    return false;
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!mounted || _notRegistered) return;
    var delay = _pollInterval;
    if (_failures > 0) {
      final secs = _pollInterval.inSeconds * (1 << _failures.clamp(0, 5));
      delay = Duration(seconds: secs);
      if (delay > _maxBackoff) delay = _maxBackoff;
    }
    _timer = Timer(delay, _pollNow);
  }

  /// Fetches messages newer than the newest one we have. Guarded so slow
  /// requests never overlap.
  Future<void> _pollNow() async {
    if (_polling || !mounted || _notRegistered || _loading) return;
    _polling = true;
    try {
      var added = <ChatMessage>[];
      var hasMore = true;
      // Catch up in chunks if more than one page arrived while away.
      for (var i = 0; i < 5 && hasMore; i++) {
        final after = _messages.isEmpty ? null : _messages.last.seq;
        final page = await _api.listEventMessagesCursor(widget.event.id,
            after: after, limit: _pageSize);
        if (!mounted) return;
        hasMore = page.hasMore && after != null;
        if (page.data.isNotEmpty) {
          added = [...added, ..._merge(page.data, live: true)];
        } else {
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _offline = false;
        _failures = 0;
        if (added.isNotEmpty && !_atBottom) {
          _unseen += added.where((m) => !_isMine(m)).length;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (_handleNotRegistered(e)) return;
      setState(() {
        _failures++;
        if (_failures >= 2) _offline = true;
      });
    } finally {
      _polling = false;
      _scheduleNext();
    }
  }

  /// Merges [incoming] into the list (dedupe by id, keep seq order). Returns
  /// the messages that were actually new.
  List<ChatMessage> _merge(List<ChatMessage> incoming, {bool live = false}) {
    final known = _messages.map((m) => m.id).toSet();
    final added = incoming.where((m) => !known.contains(m.id)).toList();
    if (added.isEmpty) return const [];
    if (live) _fresh.addAll(added.map((m) => m.id));
    _messages = [..._messages, ...added]
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return added;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // The list is reversed, so "top" (oldest) is maxScrollExtent.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadOlder();
    }
    if (_unseen > 0 && _atBottom) setState(() => _unseen = 0);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMoreOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _api.listEventMessagesCursor(widget.event.id,
          before: _messages.first.seq, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _merge(page.data);
        _hasMoreOlder = page.hasMore;
        _loadingOlder = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  // ---- sending / deleting -------------------------------------------------

  bool _isMine(ChatMessage m) {
    final me = ref.read(authProvider).user;
    return me != null && m.userId == me.id;
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send({_Pending? retry}) async {
    final text = retry?.content ?? _input.text.trim();
    if (text.isEmpty) return;

    final p = retry ?? _Pending(_nextLocalId++, text);
    setState(() {
      p.failed = false;
      if (retry == null) {
        _pending.add(p);
        _input.clear();
      }
    });
    _scrollToBottom();

    try {
      final msg = await _api.postEventMessage(widget.event.id, p.content);
      if (!mounted) return;
      setState(() {
        _pending.remove(p);
        _merge([msg], live: true);
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      if (_handleNotRegistered(e)) return;
      setState(() => p.failed = true);
    }
  }

  Future<void> _delete(ChatMessage m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(m.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteEventMessage(widget.event.id, m.id);
      if (!mounted) return;
      setState(() => _messages = _messages.where((x) => x.id != m.id).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  bool _canDelete(ChatMessage m, User? me) {
    if (me == null) return false;
    if (m.userId != null && m.userId == me.id) return true;
    if (me.role == 'super_admin') return true;
    return me.role == 'church_admin' && me.churchId == widget.event.churchId;
  }

  // ---- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final timeFmt = DateFormat.MMMd().add_jm();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.event.title} · Chat')),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _offline
                ? Container(
                    width: double.infinity,
                    color: Colors.orange.shade100,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_off, size: 16),
                        SizedBox(width: 8),
                        Text('Reconnecting…'),
                        SizedBox(width: 6),
                        _Dots(size: 5),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Expanded(child: _body(me, timeFmt)),
          if (!_notRegistered) _composer(),
        ],
      ),
    );
  }

  Widget _body(User? me, DateFormat timeFmt) {
    if (_loading) return const Center(child: _Dots(size: 10));
    if (_notRegistered) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Only registered attendees can use this chat.\n'
            'Register for the event to join the conversation.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return Center(child: Text('Error: $_error'));
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return const Center(child: Text('No messages yet. Say hello!'));
    }

    // Reversed list: index 0 is the newest item, pinned to the bottom.
    final total = _messages.length + _pending.length;
    final showOlderLoader = _loadingOlder;
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: total + (showOlderLoader ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= total) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: _Dots(size: 6)),
              );
            }
            final fromEnd = total - 1 - i; // index in oldest-first order
            if (fromEnd >= _messages.length) {
              final p = _pending[fromEnd - _messages.length];
              return _MessageBubble(
                key: ValueKey('p${p.localId}'),
                content: p.content,
                authorName: '',
                mine: true,
                timeLabel: '',
                status: p.failed ? _Status.failed : _Status.sending,
                onTap: p.failed ? () => _send(retry: p) : null,
                onLongPress: p.failed
                    ? () => setState(() => _pending.remove(p))
                    : null,
                animate: true,
              );
            }
            final m = _messages[fromEnd];
            final canDelete = _canDelete(m, me);
            return _MessageBubble(
              key: ValueKey(m.id),
              content: m.content,
              authorName: m.authorName,
              mine: me != null && m.userId == me.id,
              timeLabel: timeFmt.format(m.createdAt.toLocal()),
              animate: _fresh.contains(m.id),
              onDelete: canDelete ? () => _delete(m) : null,
              onLongPress: canDelete ? () => _delete(m) : null,
            );
          },
        ),
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _unseen > 0
                  ? ActionChip(
                      key: const ValueKey('unseen'),
                      avatar: const Icon(Icons.arrow_downward, size: 16),
                      label: Text(
                          '$_unseen new message${_unseen == 1 ? '' : 's'}'),
                      onPressed: () {
                        setState(() => _unseen = 0);
                        _scrollToBottom();
                      },
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Status { sent, sending, failed }

class _MessageBubble extends StatelessWidget {
  final String content;
  final String authorName;
  final bool mine;
  final String timeLabel;
  final _Status status;
  final bool animate;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    super.key,
    required this.content,
    required this.authorName,
    required this.mine,
    required this.timeLabel,
    this.status = _Status.sent,
    this.animate = false,
    this.onDelete,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor = status == _Status.failed
        ? scheme.errorContainer
        : mine
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;

    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine && authorName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    authorName,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              Text(content),
              const SizedBox(height: 2),
              _footer(context),
            ],
          ),
        ),
      ),
    );

    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 12), child: child),
      ),
      child: bubble,
    );
  }

  Widget _footer(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    switch (status) {
      case _Status.sending:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [_Dots(size: 4)],
        );
      case _Status.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 14, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 4),
            Text('Not sent · tap to retry', style: style),
          ],
        );
      case _Status.sent:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(timeLabel, style: style),
            if (onDelete != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    size: 14, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
        );
    }
  }
}

/// Three dots that pulse in sequence. Used while loading, sending and
/// reconnecting.
class _Dots extends StatefulWidget {
  final double size;

  const _Dots({required this.size});

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          // Each dot peaks at a different point in the cycle.
          final phase = (_c.value - i * 0.2) % 1.0;
          final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
          return Container(
            width: widget.size,
            height: widget.size,
            margin: EdgeInsets.symmetric(horizontal: widget.size * 0.3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.3 + 0.7 * t),
            ),
          );
        }),
      ),
    );
  }
}
