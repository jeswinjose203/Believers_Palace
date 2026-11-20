import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import 'community_ad_detail_screen.dart';
import 'community_ad_form_screen.dart';

class CommunityAdsBrowseScreen extends ConsumerStatefulWidget {
  const CommunityAdsBrowseScreen({super.key});

  @override
  ConsumerState<CommunityAdsBrowseScreen> createState() =>
      _CommunityAdsBrowseScreenState();
}

class _CommunityAdsBrowseScreenState extends ConsumerState<CommunityAdsBrowseScreen> {
  final _search = TextEditingController();
  List<MarketplaceCategory> _categories = [];
  String? _categoryId;
  List<CommunityAd> _ads = [];
  bool _loading = true;
  String? _error;
  bool _excludeSold = false;
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      if (_categories.isEmpty) {
        _categories = await api.listMarketplaceCategories('community');
      }
      final res = await api.browseCommunityAds(
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        categoryId: _categoryId,
        excludeSold: _excludeSold,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _ads = res.data;
        _page = res.pagination.page;
        _totalPages = res.pagination.totalPages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CommunityAdFormScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Sell an item'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(page: _page),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Search listings',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            _load();
                          },
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            value: _categoryId,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All')),
                              ..._categories.map(
                                (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() => _categoryId = v);
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Hide sold'),
                          selected: _excludeSold,
                          onSelected: (v) {
                            setState(() => _excludeSold = v);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(child: Text(_error!, textAlign: TextAlign.center)),
              )
            else if (_ads.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No listings yet.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.crossAxisExtent > 600;
                    final cross = wide ? 2 : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cross,
                        mainAxisExtent: 120,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final ad = _ads[i];
                          return _AdCard(
                            ad: ad,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CommunityAdDetailScreen(adId: ad.id),
                                ),
                              );
                              _load(page: _page);
                            },
                          );
                        },
                        childCount: _ads.length,
                      ),
                    );
                  },
                ),
              ),
            if (_totalPages > 1)
              SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Page $_page / $_totalPages'),
                    IconButton(
                      onPressed:
                          _page < _totalPages ? () => _load(page: _page + 1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  final CommunityAd ad;
  final VoidCallback onTap;

  const _AdCard({required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 100,
              height: 120,
              child: ad.images.isNotEmpty
                  ? Image.network(ad.images.first, fit: BoxFit.cover)
                  : ColoredBox(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ad.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(ad.priceLabel, style: const TextStyle(color: Color(0xFF702078))),
                    if (ad.categoryName != null)
                      Text(ad.categoryName!, style: Theme.of(context).textTheme.bodySmall),
                    if (ad.isSold)
                      const Chip(label: Text('Sold'), visualDensity: VisualDensity.compact),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}