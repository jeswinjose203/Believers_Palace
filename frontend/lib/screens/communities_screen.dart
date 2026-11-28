import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../models/community_models.dart';
import '../services/api_service.dart';
import '../services/chat_live_service.dart';
import '../services/chat_notification_service.dart';
import '../widgets/chat_notification_button.dart';
import '../widgets/group_chat_bubble.dart';
import '../widgets/image_picker_field.dart';
import '../widgets/user_error.dart';

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
        _error = userErrorMessage(e);
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
          items: [..._pages[joined]!.items, ...next.items],
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
    final api = ref.read(apiServiceProvider);
    final community = await showDialog<Community>(
      context: context,
      builder: (_) => _CommunityEditorDialog(
        save: (name, description, image) =>
            api.createCommunity(name, description, image: image),
      ),
    );
    if (community == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(community: community),
    ));
    _load();
  }

  Future<void> _open(Community community) async {
    final user = ref.read(authProvider).user;
    final notifications = ref.read(chatNotificationServiceProvider);
    if (user != null) notifications.markCommunityRead(user.id, community.id);
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(
        community: community,
        onCommunityChanged: _communityChanged,
      ),
    ));
    if (mounted) {
      if (user != null) notifications.markCommunityRead(user.id, community.id);
      if (changed == true) _load();
    }
  }

  void _communityChanged(Community community) {
    if (!mounted) return;
    setState(() {
      _pages.updateAll((_, page) => (
            items: [
              for (final current in page.items)
                current.id == community.id ? community : current,
            ],
            nextCursor: page.nextCursor,
          ));
    });
    if (_refreshing) _load();
  }

  void _showError(Object error) {
    showUserError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Communities')),
          bottom: TabBar(
            tabs: [Tab(text: context.tr('My church')), Tab(text: context.tr('Joined'))],
          ),
        ),
        floatingActionButton: user?.churchId == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Create')),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(context.tr('Could not load communities: {0}', [_error])))
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
                Center(child: Text(context.tr(emptyText))),
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
                          ? context.tr('Loading…')
                          : context.tr('Load more')),
                    ),
                  );
                }
                final community = items[index];
                final user = ref.read(authProvider).user;
                final preview = joinedOnly && user != null
                    ? ref
                        .read(chatNotificationServiceProvider)
                        .communityPreview(user.id, community.id)
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
                      ? Text(context.tr(label))
                      : Text('${preview.author}: ${preview.text}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: preview == null
                      ? const Icon(Icons.chevron_right)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(DateUtils.isSameDay(
                                    preview.time.toLocal(), DateTime.now())
                                ? DateFormat.jm(context.dateLocale).format(preview.time.toLocal())
                                : DateFormat.MMMd(context.dateLocale)
                                    .format(preview.time.toLocal())),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (preview.muted)
                                  Icon(Icons.notifications_off_outlined,
                                      size: 14, semanticLabel: context.tr('Muted')),
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

class _CommunityEditorDialog extends StatefulWidget {
  const _CommunityEditorDialog({this.community, required this.save});

  final Community? community;
  final Future<Community> Function(
      String name, String description, String? image) save;

  @override
  State<_CommunityEditorDialog> createState() => _CommunityEditorDialogState();
}

class _CommunityEditorDialogState extends State<_CommunityEditorDialog> {
  late final _name = TextEditingController(text: widget.community?.name);
  late final _description =
      TextEditingController(text: widget.community?.description);
  late String? _image = widget.community?.image;
  bool _imageUploading = false;
  bool _saving = false;
  String? _nameError;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a community name.');
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      final community =
          await widget.save(name, _description.text.trim(), _image);
      if (mounted) Navigator.pop(context, community);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showUserError(context, error,
          fallback: 'Could not save the community. Please try again.');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(context.tr(widget.community == null
              ? 'Create community'
              : 'Edit community')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 100,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                  decoration: InputDecoration(
                    labelText: context.tr('Name'),
                    errorText:
                        _nameError == null ? null : context.tr(_nameError!),
                  ),
                ),
                TextField(
                  controller: _description,
                  enabled: !_saving,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: context.tr('Description')),
                ),
                IgnorePointer(
                  ignoring: _saving,
                  child: ImagePickerField(
                    label: context.tr('Community picture (optional)'),
                    initialUrl: widget.community?.image,
                    onChanged: (value) => setState(() => _image = value),
                    onUploadingChanged: (value) =>
                        setState(() => _imageUploading = value),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(context.tr('Cancel'))),
            FilledButton(
                onPressed: _imageUploading || _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context
                        .tr(widget.community == null ? 'Create' : 'Save'))),
          ],
        ),
      );
}

class _CommunityAvatar extends StatelessWidget {
  final Community community;
  final double radius;

  const _CommunityAvatar({required this.community, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final image = community.image;
    final initial =
        community.name.isEmpty ? '?' : community.name.characters.first;
    return CircleAvatar(
      radius: radius,
      child: image == null || image.isEmpty
          ? Text(initial.toUpperCase())
          : ClipOval(
              child: Image.network(
                image,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(initial.toUpperCase()),
              ),
            ),
    );
  }
}

class _CommunityInfoScreen extends StatefulWidget {
  const _CommunityInfoScreen({
    required this.community,
    required this.api,
    required this.onChanged,
  });

  final Community community;
  final ApiService api;
  final ValueChanged<Community> onChanged;

  @override
  State<_CommunityInfoScreen> createState() => _CommunityInfoScreenState();
}

class _CommunityInfoScreenState extends State<_CommunityInfoScreen> {
  late Community _community = widget.community;

  Future<void> _edit() async {
    final updated = await showDialog<Community>(
      context: context,
      builder: (_) => _CommunityEditorDialog(
        community: _community,
        save: (name, description, image) => widget.api.updateCommunity(
          _community.id,
          name,
          description,
          image: image,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _community = updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Community info'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: _CommunityAvatar(community: _community, radius: 44)),
            const SizedBox(height: 12),
            Text(
              _community.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_community.isAdmin && _community.status == 'active') ...[
              const SizedBox(height: 12),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.tr('Edit community')),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(context.tr('Description'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            SelectableText(
              _community.description.isEmpty
                  ? context.tr('No description yet.')
                  : _community.description,
            ),
          ],
        ),
      );
}

class CommunityDetailScreen extends ConsumerStatefulWidget {
  final Community community;
  final ValueChanged<Community>? onCommunityChanged;

  const CommunityDetailScreen({
    super.key,
    required this.community,
    this.onCommunityChanged,
  });

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
  late Community _community = widget.community;
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

  void _stopWatchingMessages() {
    unawaited(_liveSubscription?.cancel());
    _liveSubscription = null;
    _live = false;
  }

  void _watchMessages() {
    if (!_active || !_appResumed || _liveSubscription != null) {
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
      if (_active) {
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
        _error = userErrorMessage(e);
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
    if (!mounted || !_active || !_appResumed) return;
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
        !_appResumed) {
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
          if (_messages.isEmpty) _error = userErrorMessage(e);
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
            SnackBar(content: Text(context.tr('Membership request sent.'))));
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

  void _showError(Object error) {
    showUserError(context, error);
  }

  void _openInfo() {
    final api = _api;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _CommunityInfoScreen(
        community: _community,
        api: api,
        onChanged: (updated) {
          if (!mounted) return;
          setState(() => _community = updated);
          widget.onCommunityChanged?.call(updated);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
        title: Tooltip(
          message: context.tr('Community info'),
          child: InkWell(
            onTap: _openInfo,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                _CommunityAvatar(community: _community),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_community.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_active)
            ChatNotificationButton(
              kind: ChatKind.community,
              id: widget.community.id,
            ),
          if (_active)
            IconButton(
                tooltip: context.tr('Leave community'),
                onPressed: _leave,
                icon: const Icon(Icons.exit_to_app)),
        ],
      ),
      body: _body(status),
    );
  }

  Widget _body(String status) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _messages.isEmpty && _active) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Could not load messages: {0}', [_error])),
            const SizedBox(height: 8),
            FilledButton(onPressed: _load, child: Text(context.tr('Retry'))),
          ],
        ),
      );
    }
    if (_error != null && !_active) {
      return Center(child: Text(context.tr('Could not load community: {0}', [_error])));
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
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 16),
                      SizedBox(width: 8),
                      Text(context.tr('Reconnecting…')),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (widget.community.isAdmin) _adminPanel(),
        Expanded(child: _chat()),
        _composer(),
      ],
    );
  }

  Widget _joinState(String status) {
    if (status == 'pending') {
      return Center(
          child: Text(context.tr('Your membership request is awaiting approval.')));
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(context.tr('Request to join this community.')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _join,
          icon: const Icon(Icons.group_add),
          label: Text(context.tr('Request to join')),
        ),
      ]),
    );
  }

  Widget _adminPanel() => ExpansionTile(
        title: Text(context.tr('Admin · {0} pending requests', [_requests.length])),
        children: [
          if (_requests.isEmpty)
            ListTile(title: Text(context.tr('No pending requests')))
          else
            ..._requests.map((request) => ListTile(
                  title: Text(request.userName),
                  subtitle: Text(context.tr('Membership request')),
                  trailing: Wrap(children: [
                    IconButton(
                        tooltip: context.tr('Approve'),
                        onPressed: () => _review(request, true),
                        icon: const Icon(Icons.check, color: Colors.green)),
                    IconButton(
                        tooltip: context.tr('Decline'),
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
                        tooltip: context.tr('Remove member'),
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
              children: [
                SizedBox(
                  height: 240,
                  child: Center(child: Text(context.tr('No messages yet. Say hello!'))),
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
                          : Text(context.tr('Load older messages')),
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
                    ? DateFormat.yMMMd(context.dateLocale).format(sentAt)
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
                  timeLabel: DateFormat.jm(context.dateLocale).format(sentAt),
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
                  label: Text(context.tr('{0} new message{1}', [_unseen, _unseen == 1 ? '' : 's'])),
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
                    hintText: context.tr('Message'),
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
