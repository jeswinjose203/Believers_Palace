import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'church_detail_screen.dart';
import 'churches_screen.dart' show ChurchFormDialog;

const _kPurple = Color(0xFF702078);
const _kPurpleDark = Color(0xFF3F1F4A);
const _kTint = Color(0xFFF6EEF7);

/// "Find your church": the landing tab for members after login. Lists
/// churches (filtered by the search box) as cards; "View church" opens the
/// full church details page.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Future<PaginatedResponse<Church>>? _future;
  // Incremented whenever a church is created/edited so the list cards are
  // force-rebuilt and show the latest image immediately after Save.
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<PaginatedResponse<Church>> _load() => ref
      .read(apiServiceProvider)
      .listChurches(search: _search.text.trim(), limit: 50);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {}
  }

  /// Refresh after a create/edit: evict cached network images and bump the
  /// reload token so every card rebuilds and fetches its (possibly new) image
  /// immediately, without needing to leave and re-enter the page.
  Future<void> _refreshAfterEdit() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    setState(() {
      _reloadToken++;
      _future = _load();
    });
    try {
      await _future;
    } catch (_) {}
  }

  void _onChanged(String _) {
    setState(() {}); // toggles the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _future = _load());
    });
  }

  void _clear() {
    _search.clear();
    _debounce?.cancel();
    setState(() => _future = _load());
  }

  void _open(Church c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChurchDetailScreen(church: c)),
    );
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Opens the Add/Edit church form (admins/super_admin only). On an edit the
  /// full record is loaded first so the form is prefilled.
  Future<void> _createOrEdit({Church? existing}) async {
    Church? full = existing;
    if (existing != null) {
      try {
        full = await ref.read(apiServiceProvider).getChurch(existing.id);
      } catch (e) {
        _toast('Could not load church details: $e');
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ChurchFormDialog(existing: full),
    );
    if (saved == true) _refreshAfterEdit();
  }

  /// Deletes a church (super_admin only) after confirmation.
  Future<void> _delete(Church c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
            'This permanently removes the church and is not reversible.'),
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
      await ref.read(apiServiceProvider).deleteChurch(c.id);
      _toast('Church deleted');
      _refresh();
    } catch (e) {
      _toast(e.toString());
    }
  }

  /// Heart: make this the member's church (shown on the Home tab).
  Future<void> _setMyChurch(Church c) async {
    final user = ref.read(authProvider).user;
    if (user?.churchId == c.id) {
      _toast('${c.name} is already your church');
      return;
    }
    try {
      await ref.read(authProvider.notifier).updateProfile({'churchId': c.id});
      _toast('${c.name} set as your church');
    } catch (e) {
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final myChurchId = user?.churchId;
    final isSuperAdmin = user?.role == 'super_admin';

    bool canManage(Church c) =>
        isSuperAdmin ||
        (user?.role == 'church_admin' && user?.churchId == c.id);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Add Church'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Find your church',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'A community to connect, pray and gather.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _refresh(),
                  decoration: InputDecoration(
                    hintText: 'Search by church name or place',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _clear,
                          ),
                    filled: true,
                    fillColor: const Color(0xFFF3F1F4),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<PaginatedResponse<Church>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Error: ${snap.error}',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          FilledButton(
                              onPressed: _refresh, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  );
                }
                final churches = snap.data?.data ?? [];
                final total = snap.data?.pagination.total ?? churches.length;
                if (churches.isEmpty) {
                  return const Center(child: Text('No churches found.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: churches.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            total == 1 ? '1 church' : '$total churches',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        );
                      }
                      final c = churches[i - 1];
                      return _ChurchCard(
                        // Key includes the image reference so the card (and its
                        // Image.network) rebuilds when the image changes.
                        key: ValueKey(
                            '$_reloadToken|${c.id}|${c.images.isNotEmpty ? c.images.first : c.logo ?? ''}'),
                        church: c,
                        isMine: c.id == myChurchId,
                        canManage: canManage(c),
                        canDelete: isSuperAdmin,
                        onView: () => _open(c),
                        onHeart: () => _setMyChurch(c),
                        onEdit: () => _createOrEdit(existing: c),
                        onDelete: () => _delete(c),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChurchCard extends StatelessWidget {
  final Church church;
  final bool isMine;
  final bool canManage;
  final bool canDelete;
  final VoidCallback onView;
  final VoidCallback onHeart;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ChurchCard({
    super.key,
    required this.church,
    required this.isMine,
    required this.canManage,
    required this.canDelete,
    required this.onView,
    required this.onHeart,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Prefer a gallery image, then the logo. If the primary image fails to
    // load (e.g. the file is missing) fall back to the logo, then a
    // placeholder, so a broken gallery URL doesn't hide an available logo.
    final gallery =
        church.images.isNotEmpty ? church.images.first : null;
    final logo = (church.logo ?? '').isNotEmpty ? church.logo : null;
    final primary = gallery ?? logo;
    final fallbackUrl = (gallery != null) ? logo : null;
    final address = church.address ?? '';
    final description = church.description ?? '';

    final placeholder = Container(
      color: const Color(0xFFE8DCE9),
      child: const Center(child: Icon(Icons.church, size: 56, color: _kPurple)),
    );

    Widget buildImage(String url, {required Widget onError}) => Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => onError,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onView,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 160,
                width: double.infinity,
                child: primary == null
                    ? placeholder
                    : buildImage(
                        primary,
                        onError: fallbackUrl != null
                            ? buildImage(fallbackUrl, onError: placeholder)
                            : placeholder,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            church.name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _kPurple),
                          ),
                          if (address.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 14, color: Colors.black54),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (canManage)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: _kPurple),
                        onSelected: (v) {
                          if (v == 'edit') onEdit();
                          if (v == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          if (canDelete)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: isMine ? null : onHeart,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPurple,
                          side: const BorderSide(color: _kPurple),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(isMine ? 'Your church' : 'Set my church'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onView,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPurpleDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('View church  →'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
