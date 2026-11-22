import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/auth_provider.dart';
import '../models/community_models.dart';
import '../services/api_service.dart';
import '../services/chat_live_service.dart';
import '../services/chat_notification_service.dart';
import '../widgets/chat_email_verification.dart';
import '../widgets/chat_notification_button.dart';
import '../widgets/group_chat_bubble.dart';
import '../widgets/image_picker_field.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  final _pages = <bool, CommunityPage>{};
  final _loadingMore = <bool>{};
  int _loadVersion = 0;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final version = ++_loadVersion;
    final api = ref.read(apiServiceProvider);
    setState(() {
      _refreshing = true;
      _loadingMore.clear();
    });
    try {
      final pages = await Future.wait([
        api.listCommunityPage(joined: false),
        api.listCommunityPage(joined: true),
      ]);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _pages[false] = pages[0];
        _pages[true] = pages[1];
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore(bool joined) async {
    final page = _pages[joined];
    final cursor = page?.nextCursor;
    if (_refreshing ||
        page == null ||
        cursor == null ||
        _loadingMore.contains(joined)) {
      return;
    }
    final version = _loadVersion;
    setState(() => _loadingMore.add(joined));
    try {
      final next = await ref.read(apiServiceProvider).listCommunityPage(
            joined: joined,
            cursor: cursor,
          );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _pages[joined] = (
          items: [...page.items, ...next.items],
          nextCursor: next.nextCursor,
        );
      });
    } catch (error) {
      if (mounted && version == _loadVersion) _showError(error);
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _loadingMore.remove(joined));
      }
    }
  }

  Future<void> _create() async {
    final values = await showDialog<_CreateCommunityValues>(
      context: context,
      builder: (_) => const _CreateCommunityDialog(),
    );
    if (values == null || values.name.isEmpty) return;
    try {
      final community = await ref.read(apiServiceProvider).createCommunity(
            values.name,
            values.description,
            image: values.image,
          );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(community: community),
      ));
      _load();
    } catch (e) {
      if (mounted) _showError(e);
    }
  }

  Future<void> _open(Community community) async {
    final user = ref.read(authProvider).user;
    final notifications = ref.read(chatNotificationServiceProvider);
    if (user != null) notifications.markCommunityRead(user.id, community.id);
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(community: community),
    ));
    if (mounted) {
      if (user != null) notifications.markCommunityRead(user.id, community.id);
      if (changed == true) _load();
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communities'),
          bottom: const TabBar(
            tabs: [Tab(text: 'My church'), Tab(text: 'Joined')],
          ),
        ),
        floatingActionButton: user?.churchId == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Could not load communities: $_error'))
                : TabBarView(
                    children: [
                      _communityList(joinedOnly: false),
                      ValueListenableBuilder(
                        valueListenable:
                            ref.read(chatNotificationServiceProvider).previews,
                        builder: (_, previews, __) =>
                            _communityList(joinedOnly: true),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _communityList({required bool joinedOnly}) {
    final page = _pages[joinedOnly];
    final items = page?.items ?? const <Community>[];
    final hasMore = page?.nextCursor != null;
    final emptyText = joinedOnly
        ? 'You haven’t joined any communities yet.'
        : ref.watch(authProvider).user?.churchId == null
            ? 'Select a church to discover its communities.'
            : 'No communities yet for this church.';
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 180),
                Center(child: Text(emptyText)),
              ],
            )
          : ListView.builder(
              key: PageStorageKey(joinedOnly),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: items.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Center(
                    child: TextButton(
                      onPressed: _loadingMore.contains(joinedOnly)
                          ? null
                          : () => _loadMore(joinedOnly),
                      child: Text(_loadingMore.contains(joinedOnly)
                          ? 'Loading…'
                          : 'Load more'),
                    ),
                  );
                }
                final community = items[index];
                final user = ref.read(authProvider).user;
                final preview = joinedOnly && user?.emailVerified == true
                    ? ref
                        .read(chatNotificationServiceProvider)
                        .communityPreview(user?.id, community.id)
                    : null;
                final label = community.isAdmin
                    ? 'Admin'
                    : community.status == 'active'
                        ? 'Member'
                        : community.status == 'pending'
                            ? 'Request pending'
                            : 'Open';
                return ListTile(
                  leading: _CommunityAvatar(community: community),
                  title: Text(community.name),
                  subtitle: preview == null
                      ? Text(community.description.isEmpty
                          ? label
                          : '${community.description}\n$label')
                      : Text('${preview.author}: ${preview.text}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  isThreeLine:
                      preview == null && community.description.isNotEmpty,
                  trailing: preview == null
                      ? const Icon(Icons.chevron_right)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(DateUtils.isSameDay(
                                    preview.time.toLocal(), DateTime.now())
                                ? DateFormat.jm().format(preview.time.toLocal())
                                : DateFormat.MMMd()
                                    .format(preview.time.toLocal())),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (preview.muted)
                                  const Icon(Icons.notifications_off_outlined,
                                      size: 14, semanticLabel: 'Muted'),
                                if (preview.unread > 0)
                                  Badge(label: Text('${preview.unread}')),
                              ],
                            ),
                          ],
                        ),
                  onTap: () => _open(community),
                );
              },
            ),
    );
  }
}

class _CreateCommunityDialog extends StatefulWidget {
  const _CreateCommunityDialog();

  @override
  State<_CreateCommunityDialog> createState() => _CreateCommunityDialogState();
}

class _CreateCommunityDialogState extends State<_CreateCommunityDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _image;
  bool _imageUploading = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create community'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: _description,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              ImagePickerField(
                label: 'Community picture (optional)',
                onChanged: (value) => setState(() => _image = value),
                onUploadingChanged: (value) =>
                    setState(() => _imageUploading = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _imageUploading
                  ? null
                  : () => Navigator.pop(
                        context,
                        _CreateCommunityValues(
                          name: _name.text.trim(),
                          description: _description.text,
                          image: _image,
                        ),
                      ),
              child: const Text('Create')),
        ],
      );
}

class _CreateCommunityValues {
  final String name;
  final String description;
  final String? image;

  const _CreateCommunityValues({
    required this.name,
    required this.description,
    this.image,
  });
}

class _CommunityAvatar extends StatelessWidget {
  final Community community;

  const _CommunityAvatar({required this.community});

  @override
  Widget build(BuildContext context) {
    final image = community.image;
    final initial = community.name.isEmpty ? '?' : community.name[0];
    return CircleAvatar(
      child: image == null || image.isEmpty
          ? Text(initial.toUpperCase())
          : ClipOval(
              child: Image.network(
                image,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(initial.toUpperCase()),
              ),
            ),
    );
  }
}

class CommunityDetailScreen extends ConsumerStatefulWidget {
  final Community community;

  const CommunityDetailScreen({super.key, required this.community});

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen>
    with WidgetsBindingObserver {
  static const _pageSize = 50;
  static const _pollInterval = Duration(seconds: 3);
  static const _maxBackoff = Duration(seconds: 30);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<CommunityMessage> _messages = [];
  List<CommunityMembership> _requests = [];
  List<CommunityMembership> _members = [];
  final List<_PendingCommunityMessage> _pending = [];
  final Set<String> _fresh = {};
  bool _loading = true;
  bool _working = false;
  bool _hasMore = false;
  bool _polling = false;
  bool _appResumed = true;
  bool _offline = false;
  int _failures = 0;
  int _unseen = 0;
  int _nextLocalId = 0;
  String? _error;
  late final bool _active =
      widget.community.status == 'active' || widget.community.isAdmin;
  Timer? _timer;
  StreamSubscription<ChatChange?>? _liveSubscription;
  bool _live = false;
  bool _catchUp = false;
  int _syncedSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      _watchMessages();
      _poll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appResumed = false;
      _timer?.cancel();
      _stopWatchingMessages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopWatchingMessages();
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  bool get _emailVerified => ref.read(authProvider).user?.emailVerified == true;

  void _stopWatchingMessages() {
    unawaited(_liveSubscription?.cancel());
    _liveSubscription = null;
    _live = false;
  }

  void _watchMessages() {
    if (!_active ||
        !_emailVerified ||
        !_appResumed ||
        _liveSubscription != null) {
      return;
    }
    _liveSubscription = ref
        .read(chatLiveProvider)
        .watch('community', widget.community.id)
        .listen((change) {
      if (!mounted) return;
      _live = change != null;
      if (!_live) {
        if (_timer?.isActive != true) _scheduleNext();
        return;
      }
      _timer?.cancel();
      final deleted = change?.deleted;
      if (deleted != null) {
        setState(
            () => _messages.removeWhere((message) => message.id == deleted));
      }
      if (_polling || _loading) {
        _catchUp = true;
      } else {
        unawaited(_poll());
      }
    });
  }

  Future<void> _load() async {
    try {
      if (_active && _emailVerified) {
        final page = await _api.listCommunityMessages(widget.community.id);
        if (!mounted) return;
        setState(() {
          _messages = page.data;
          _syncedSeq = page.data.lastOrNull?.seq ?? 0;
          _hasMore = page.hasMore;
        });
      }
      if (widget.community.isAdmin) await _loadAdminLists();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _offline = false;
          _failures = 0;
        });
        if (_active) _scrollToBottom(animate: false);
        _watchMessages();
        _scheduleNext();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _failures++;
      });
      _scheduleNext();
    }
  }

  Future<void> _loadAdminLists() async {
    final results = await Future.wait([
      _api.listCommunityRequests(widget.community.id),
      _api.listCommunityMembers(widget.community.id),
    ]);
    if (!mounted) return;
    setState(() {
      _requests = results[0];
      _members = results[1];
    });
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!mounted || !_active || !_appResumed || !_emailVerified) return;
    if (_catchUp && _failures == 0) {
      _catchUp = false;
      _timer = Timer(Duration.zero, _poll);
      return;
    }
    if (_live && _failures == 0) return;
    var delay = _pollInterval;
    if (_failures > 0) {
      final seconds = _pollInterval.inSeconds * (1 << _failures.clamp(0, 5));
      delay = Duration(seconds: seconds);
      if (delay > _maxBackoff) delay = _maxBackoff;
    }
    _timer = Timer(delay, _poll);
  }

  bool get _atBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels < 60;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels <= 120 && _hasMore) _loadOlder();
    if (_unseen > 0 && _atBottom) setState(() => _unseen = 0);
  }

  void _scrollToBottom({bool animate = true}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _poll() async {
    if (!_active ||
        _polling ||
        _loading ||
        !mounted ||
        !_appResumed ||
        !_emailVerified) {
      return;
    }
    _polling = true;
    try {
      var cursor = _syncedSeq;
      var hasMore = true;
      final incoming = <CommunityMessage>[];
      for (var pageIndex = 0; pageIndex < 5 && hasMore; pageIndex++) {
        final page = await _api.listCommunityMessages(
          widget.community.id,
          after: cursor,
          limit: _pageSize,
        );
        if (!mounted) return;
        if (page.data.isEmpty) break;
        incoming.addAll(page.data);
        cursor = page.data.last.seq;
        hasMore = page.hasMore;
      }
      if (!mounted) return;
      final known = _messages.map((message) => message.id).toSet();
      final fresh = incoming.where((message) => known.add(message.id)).toList();
      final userId = ref.read(authProvider).user?.id;
      final confirmed = incoming
          .where((message) => message.userId == userId)
          .map((message) => message.clientId)
          .toSet();
      final wasAtBottom = _atBottom;
      setState(() {
        _syncedSeq = cursor;
        _pending.removeWhere((message) => confirmed.contains(message.clientId));
        _offline = false;
        _failures = 0;
        _error = null;
        if (fresh.isNotEmpty) {
          _fresh.addAll(fresh.map((message) => message.id));
          _messages = [..._messages, ...fresh]
            ..sort((a, b) => a.seq.compareTo(b.seq));
          if (!wasAtBottom) {
            _unseen += fresh
                .where((message) =>
                    message.userId != ref.read(authProvider).user?.id)
                .length;
          }
        }
      });
      if (fresh.isNotEmpty && wasAtBottom) _scrollToBottom();
      if (hasMore && incoming.length >= 5 * _pageSize) _catchUp = true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _failures++;
          _offline = _failures >= 2;
          if (_messages.isEmpty) _error = e.toString();
        });
      }
    } finally {
      _polling = false;
      _scheduleNext();
    }
  }

  Future<void> _loadOlder() async {
    if (!_active || !_hasMore || _messages.isEmpty || _working) return;
    final oldMaxExtent =
        _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() => _working = true);
    try {
      final page = await _api.listCommunityMessages(widget.community.id,
          before: _messages.first.seq);
      if (!mounted) return;
      setState(() {
        final existing = _messages.map((message) => message.id).toSet();
        final older =
            page.data.where((message) => existing.add(message.id)).toList();
        _messages = [...older, ..._messages];
        _hasMore = page.hasMore;
      });
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          final addedExtent = _scroll.position.maxScrollExtent - oldMaxExtent;
          _scroll.jumpTo(oldOffset + addedExtent);
        }
      });
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _join() async {
    try {
      await _api.requestCommunityMembership(widget.community.id);
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Membership request sent.')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _send({_PendingCommunityMessage? retry}) async {
    final content = retry?.content ?? _input.text.trim();
    if (content.isEmpty) return;
    final pending = retry ?? _PendingCommunityMessage(_nextLocalId++, content);
    setState(() {
      pending.failed = false;
      if (retry == null) {
        _pending.add(pending);
        _input.clear();
      }
    });
    _scrollToBottom();
    try {
      final message = await _api.postCommunityMessage(
          widget.community.id, pending.content,
          clientId: pending.clientId);
      if (!mounted) return;
      setState(() {
        _pending.remove(pending);
        if (_messages.every((item) => item.id != message.id)) {
          _fresh.add(message.id);
          _messages = [..._messages, message];
          _messages.sort((a, b) => a.seq.compareTo(b.seq));
        }
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => pending.failed = true);
    }
  }

  Future<void> _review(CommunityMembership request, bool approve) async {
    try {
      await _api.reviewCommunityRequest(
          widget.community.id, request.id, approve);
      await _loadAdminLists();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _remove(CommunityMembership member) async {
    try {
      await _api.removeCommunityMember(widget.community.id, member.userId);
      await _loadAdminLists();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _leave() async {
    try {
      await _api.leaveCommunity(widget.community.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _delete(CommunityMessage message) async {
    try {
      await _api.deleteCommunityMessage(widget.community.id, message.id);
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == message.id));
      }
    } catch (e) {
      _showError(e);
    }
  }

  bool _canDelete(CommunityMessage message) {
    final user = ref.read(authProvider).user;
    return widget.community.isAdmin ||
        (user != null && message.userId == user.id);
  }

  void _showError(Object error) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));

  @override
  Widget build(BuildContext context) {
    final verified = ref.watch(
      authProvider.select((state) => state.user?.emailVerified == true),
    );
    ref.listen(
      authProvider.select((state) => state.user?.emailVerified == true),
      (_, verified) {
        if (verified && _active) {
          _load();
        } else if (!verified) {
          _stopWatchingMessages();
        }
      },
    );
    final status = widget.community.status;
    final subtitle = _active
        ? widget.community.isAdmin
            ? '${_members.length} member${_members.length == 1 ? '' : 's'}'
            : 'Group chat'
        : status == 'pending'
            ? 'Membership request pending'
            : 'Request to join';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _CommunityAvatar(community: widget.community),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.community.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_active && verified)
            ChatNotificationButton(
              kind: ChatKind.community,
              id: widget.community.id,
            ),
          if (_active)
            IconButton(
                tooltip: 'Leave community',
                onPressed: _leave,
                icon: const Icon(Icons.exit_to_app)),
        ],
      ),
      body: _body(status, verified),
    );
  }

  Widget _body(String status, bool verified) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _messages.isEmpty && _active) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load messages: $_error'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_error != null && !_active) {
      return Center(child: Text('Could not load community: $_error'));
    }
    if (!_active) return _joinState(status);

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _offline
              ? Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_off, size: 16),
                      SizedBox(width: 8),
                      Text('Reconnecting…'),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (widget.community.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.community.description,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        if (widget.community.isAdmin) _adminPanel(),
        Expanded(
          child: verified ? _chat() : const ChatEmailVerification(),
        ),
        if (verified) _composer(),
      ],
    );
  }

  Widget _joinState(String status) {
    if (status == 'pending') {
      return const Center(
          child: Text('Your membership request is awaiting approval.'));
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.community.description.isEmpty
            ? 'Request to join this community.'
            : widget.community.description),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _join,
          icon: const Icon(Icons.group_add),
          label: const Text('Request to join'),
        ),
      ]),
    );
  }

  Widget _adminPanel() => ExpansionTile(
        title: Text('Admin · ${_requests.length} pending requests'),
        children: [
          if (_requests.isEmpty)
            const ListTile(title: Text('No pending requests'))
          else
            ..._requests.map((request) => ListTile(
                  title: Text(request.userName),
                  subtitle: const Text('Membership request'),
                  trailing: Wrap(children: [
                    IconButton(
                        tooltip: 'Approve',
                        onPressed: () => _review(request, true),
                        icon: const Icon(Icons.check, color: Colors.green)),
                    IconButton(
                        tooltip: 'Decline',
                        onPressed: () => _review(request, false),
                        icon: const Icon(Icons.close, color: Colors.red)),
                  ]),
                )),
          if (_members.isNotEmpty)
            ..._members
                .where((member) => !member.isAdmin)
                .map((member) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(member.userName),
                      trailing: IconButton(
                        tooltip: 'Remove member',
                        onPressed: () => _remove(member),
                        icon: const Icon(Icons.person_remove_outlined),
                      ),
                    )),
        ],
      );

  Widget _chat() => Stack(
        children: [
          if (_messages.isEmpty && _pending.isEmpty)
            ListView(
              controller: _scroll,
              children: const [
                SizedBox(
                  height: 240,
                  child: Center(child: Text('No messages yet. Say hello!')),
                ),
              ],
            )
          else
            ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount:
                  _messages.length + _pending.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (_hasMore && index == 0) {
                  return Center(
                    child: TextButton(
                      onPressed: _loadOlder,
                      child: _working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Load older messages'),
                    ),
                  );
                }
                final messageIndex = index - (_hasMore ? 1 : 0);
                if (messageIndex >= _messages.length) {
                  final pending = _pending[messageIndex - _messages.length];
                  return GroupChatBubble(
                    key: ValueKey('pending-${pending.localId}'),
                    content: pending.content,
                    authorName: '',
                    mine: true,
                    timeLabel: '',
                    status: pending.failed
                        ? ChatSendStatus.failed
                        : ChatSendStatus.sending,
                    onRetry:
                        pending.failed ? () => _send(retry: pending) : null,
                    onLongPress: pending.failed
                        ? () => setState(() => _pending.remove(pending))
                        : null,
                    animate: true,
                  );
                }
                final message = _messages[messageIndex];
                final previous =
                    messageIndex > 0 ? _messages[messageIndex - 1] : null;
                final sentAt = message.createdAt.toLocal();
                final previousSentAt = previous?.createdAt.toLocal();
                final dateDivider = previousSentAt == null ||
                        sentAt.year != previousSentAt.year ||
                        sentAt.month != previousSentAt.month ||
                        sentAt.day != previousSentAt.day
                    ? DateFormat.yMMMd().format(sentAt)
                    : null;
                final mine = message.userId == ref.read(authProvider).user?.id;
                final canDelete = _canDelete(message);
                return GroupChatBubble(
                  key: ValueKey(message.id),
                  groupedWithPrevious: dateDivider == null &&
                      messageIndex > 0 &&
                      message.userId != null &&
                      message.userId == _messages[messageIndex - 1].userId,
                  content: message.content,
                  authorName: message.authorName,
                  mine: mine,
                  timeLabel: DateFormat.jm().format(sentAt),
                  dateDivider: dateDivider,
                  animate: _fresh.contains(message.id),
                  onDelete: canDelete ? () => _delete(message) : null,
                  onLongPress: canDelete ? () => _delete(message) : null,
                );
              },
            ),
          if (_unseen > 0)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: ActionChip(
                  avatar: const Icon(Icons.arrow_downward, size: 16),
                  label: Text('$_unseen new message${_unseen == 1 ? '' : 's'}'),
                  onPressed: () {
                    setState(() => _unseen = 0);
                    _scrollToBottom();
                  },
                ),
              ),
            ),
        ],
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: _send, icon: const Icon(Icons.send_rounded)),
            ],
          ),
        ),
      );
}

class _PendingCommunityMessage {
  final int localId;
  final String clientId = newChatMessageId();
  final String content;
  bool failed = false;

  _PendingCommunityMessage(this.localId, this.content);
}
