import 'dart:async';

import 'package:flutter/material.dart';
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
/// Delivery uses lightweight polling (every few seconds) plus pull-to-refresh,
/// fitting the REST backend without a persistent socket connection.
class EventChatScreen extends ConsumerStatefulWidget {
  final Event event;

  const EventChatScreen({super.key, required this.event});

  @override
  ConsumerState<EventChatScreen> createState() => _EventChatScreenState();
}

class _EventChatScreenState extends ConsumerState<EventChatScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _notRegistered = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    // Poll for new messages every 5 seconds.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final res = await ref
          .read(apiServiceProvider)
          .listEventMessages(widget.event.id, limit: 100);
      if (!mounted) return;
      final atBottom = !_scrollController.hasClients ||
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 40;
      setState(() {
        _messages = res.data;
        _loading = false;
        _error = null;
      });
      // Keep the view pinned to the newest message when already at the bottom.
      if (initial || atBottom) _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'not_registered') {
        // Not registered for this event: stop polling and show a prompt.
        _poll?.cancel();
        setState(() {
          _loading = false;
          _notRegistered = true;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiServiceProvider).postEventMessage(widget.event.id, text);
      _input.clear();
      await _load();
      _jumpToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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
      await ref
          .read(apiServiceProvider)
          .deleteEventMessage(widget.event.id, m.id);
      await _load();
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

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final timeFmt = DateFormat.MMMd().add_jm();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.event.title} · Chat')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _notRegistered
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Only registered attendees can use this chat.\n'
                            'Register for the event to join the conversation.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _error != null && _messages.isEmpty
                    ? Center(child: Text('Error: $_error'))
                    : _messages.isEmpty
                        ? const Center(
                            child: Text('No messages yet. Say hello!'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length,
                              itemBuilder: (context, i) {
                                final m = _messages[i];
                                final mine =
                                    me != null && m.userId == me.id;
                                return _MessageBubble(
                                  message: m,
                                  mine: mine,
                                  timeLabel: timeFmt.format(m.createdAt.toLocal()),
                                  onDelete: _canDelete(m, me)
                                      ? () => _delete(m)
                                      : null,
                                );
                              },
                            ),
                          ),
          ),
          if (!_notRegistered)
          SafeArea(
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
                  _sending
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          icon: const Icon(Icons.send),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final String timeLabel;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.timeLabel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onDelete,
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
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    message.authorName,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              Text(message.content),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onDelete,
                      child: Icon(Icons.delete_outline,
                          size: 14,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
