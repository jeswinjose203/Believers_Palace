import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth_provider.dart';
import '../../../models/models.dart';
import '../models/catechism_models.dart';
import '../services/catechism_api.dart';
import '../widgets/class_card.dart';
import 'catechism_detail_screen.dart';
import 'manage_class_form_screen.dart';
import 'my_enrollments_screen.dart';

bool canManageCatechismContent(User? user, String churchId) {
  if (user == null) return false;
  if (user.role == 'super_admin') return true;
  const staff = {'priest', 'associate_priest', 'church_admin'};
  return staff.contains(user.role) && user.churchId == churchId;
}

class CatechismListScreen extends ConsumerStatefulWidget {
  final String churchId;

  const CatechismListScreen({super.key, required this.churchId});

  @override
  ConsumerState<CatechismListScreen> createState() => _CatechismListScreenState();
}

class _CatechismListScreenState extends ConsumerState<CatechismListScreen> {
  final _search = TextEditingController();
  String? _status;
  String? _level;
  int _page = 1;
  final List<CatechismClass> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
  if (reset) {
      _page = 1;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore && !reset) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(catechismApiProvider);
      final res = await api.listClasses(
        widget.churchId,
        page: _page,
        limit: 20,
        search: _search.text.trim(),
        status: _status,
        level: _level,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(res.data);
        _hasMore = _page < res.pagination.totalPages;
        _page++;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openDetail(CatechismClass item, bool canManage) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatechismDetailScreen(classId: item.id, canManage: canManage),
      ),
    ).then((_) => _load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final canManage = canManageCatechismContent(user, widget.churchId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catechism'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'My enrollments',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyEnrollmentsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ManageClassFormScreen(churchId: widget.churchId),
                  ),
                );
                _load(reset: true);
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search classes',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _load(reset: true),
                ),
              ),
              onSubmitted: (_) => _load(reset: true),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                DropdownButton<String?>(
                  value: _status,
                  hint: const Text('Status'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All statuses')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                  ],
                  onChanged: (v) {
                    setState(() => _status = v);
                    _load(reset: true);
                  },
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _level,
                  hint: const Text('Level'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All levels')),
                    DropdownMenuItem(value: 'first_communion', child: Text('First Communion')),
                    DropdownMenuItem(value: 'confirmation', child: Text('Confirmation')),
                    DropdownMenuItem(value: 'sunday_school', child: Text('Sunday school')),
                  ],
                  onChanged: (v) {
                    setState(() => _level = v);
                    _load(reset: true);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: _error != null && _items.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => _load(reset: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _items.isEmpty && _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? const ListView(
                              children: [
                                SizedBox(height: 48),
                                Center(child: Text('No classes yet.')),
                              ],
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: (n) {
                                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 120) {
                                  _load();
                                }
                                return false;
                              },
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _items.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i >= _items.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }
                                  final item = _items[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: CatechismClassCard(
                                      item: item,
                                      onTap: () => _openDetail(item, canManage),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ),
        ],
      ),
    );
  }
}