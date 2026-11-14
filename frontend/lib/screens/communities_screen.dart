import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/community_models.dart';
import '../services/api_service.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen> {
  List<Community> _communities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiServiceProvider).listCommunities();
      if (!mounted) return;
      setState(() {
        _communities = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _create() async {
    final values = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _CreateCommunityDialog(),
    );
    if (values == null || values.first.isEmpty) return;
    try {
      final community = await ref
          .read(apiServiceProvider)
          .createCommunity(values[0], values[1]);
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
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CommunityDetailScreen(community: community),
    ));
    if (changed == true) _load();
  }

  void _showError(Object error) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('Communities')),
      floatingActionButton: user == null
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _communities.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No communities yet.')),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _communities.length,
                          itemBuilder: (context, index) {
                            final community = _communities[index];
                            final label = community.isAdmin
                                ? 'Admin'
                                : community.status == 'active'
                                    ? 'Member'
                                    : community.status == 'pending'
                                        ? 'Request pending'
                                        : 'Open';
                            return ListTile(
                              leading: CircleAvatar(
                                  child: Text(community.name.isEmpty
                                      ? '?'
                                      : community.name[0].toUpperCase())),
                              title: Text(community.name),
                              subtitle: Text(community.description.isEmpty
                                  ? label
                                  : '${community.description}\n$label'),
                              isThreeLine: community.description.isNotEmpty,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _open(community),
                            );
                          },
                        ),
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

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create community'),
        content: Column(
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
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, [_name.text.trim(), _description.text]),
              child: const Text('Create')),
        ],
      );
}

class CommunityDetailScreen extends ConsumerStatefulWidget {
  final Community community;

  const CommunityDetailScreen({super.key, required this.community});

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<CommunityMessage> _messages = [];
  List<CommunityMembership> _requests = [];
  List<CommunityMembership> _members = [];
  bool _loading = true;
  bool _working = false;
  bool _hasMore = false;
  bool _polling = false;
  String? _error;
  late final bool _active =
      widget.community.status == 'active' || widget.community.isAdmin;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> _load() async {
    try {
      if (_active) {
        final page = await _api.listCommunityMessages(widget.community.id);
        if (!mounted) return;
        setState(() {
          _messages = page.data;
          _hasMore = page.hasMore;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
        if (widget.community.isAdmin) await _loadAdminLists();
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
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

  Future<void> _poll() async {
    if (!_active || _polling || _loading || !mounted) return;
    _polling = true;
    try {
      var after = _messages.isEmpty ? null : _messages.last.seq;
      final page =
          await _api.listCommunityMessages(widget.community.id, after: after);
      if (!mounted) return;
      final known = _messages.map((m) => m.id).toSet();
      final fresh = page.data.where((m) => !known.contains(m.id)).toList();
      if (fresh.isNotEmpty) {
        final atBottom = !_scroll.hasClients ||
            _scroll.position.maxScrollExtent - _scroll.position.pixels < 60;
        setState(() {
          _messages = [..._messages, ...fresh]
            ..sort((a, b) => a.seq.compareTo(b.seq));
        });
        if (atBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(_scroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut);
            }
          });
        }
      }
    } catch (_) {
      // Keep the last messages visible; the next poll will retry.
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadOlder() async {
    if (!_active || !_hasMore || _messages.isEmpty || _working) return;
    setState(() => _working = true);
    try {
      final page = await _api.listCommunityMessages(widget.community.id,
          before: _messages.first.seq);
      if (!mounted) return;
      setState(() {
        _messages = [...page.data, ..._messages];
        _hasMore = page.hasMore;
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

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty) return;
    _input.clear();
    try {
      final message =
          await _api.postCommunityMessage(widget.community.id, content);
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => m.id == message.id)) {
          _messages = [..._messages, message];
        }
      });
    } catch (e) {
      if (mounted) {
        _input.text = content;
        _showError(e);
      }
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
    final status = widget.community.status;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.community.name),
        actions: [
          if (_active)
            IconButton(
                tooltip: 'Leave community',
                onPressed: _leave,
                icon: const Icon(Icons.exit_to_app)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load community: $_error'))
              : !_active
                  ? _joinState(status)
                  : Column(
                      children: [
                        if (widget.community.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(widget.community.description),
                          ),
                        if (widget.community.isAdmin) _adminPanel(),
                        Expanded(child: _chat()),
                        _composer(),
                      ],
                    ),
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

  Widget _chat() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (_hasMore && index == 0) {
            return TextButton(
                onPressed: _loadOlder,
                child: const Text('Load older messages'));
          }
          final offset = _hasMore ? index - 1 : index;
          final message = _messages[offset];
          final mine = message.userId == ref.read(authProvider).user?.id;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Card(
              color: mine
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine)
                      Text(message.authorName,
                          style: Theme.of(context).textTheme.labelSmall),
                    Text(message.content),
                    if (_canDelete(message))
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () => _delete(message),
                          child: const Icon(Icons.delete_outline, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                    hintText: 'Message', border: OutlineInputBorder()),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
          ]),
        ),
      );
}
