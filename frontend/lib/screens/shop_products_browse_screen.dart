import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import 'shop_product_detail_screen.dart';

class ShopProductsBrowseScreen extends ConsumerStatefulWidget {
  const ShopProductsBrowseScreen({super.key});

  @override
  ConsumerState<ShopProductsBrowseScreen> createState() =>
      _ShopProductsBrowseScreenState();
}

class _ShopProductsBrowseScreenState extends ConsumerState<ShopProductsBrowseScreen> {
  final _search = TextEditingController();
  List<MarketplaceCategory> _categories = [];
  String? _categoryId;
  List<ShopProduct> _products = [];
  bool _loading = true;
  String? _error;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      if (_categories.isEmpty) {
        _categories = await api.listMarketplaceCategories('shop');
      }
      final res = await api.browseShopProducts(
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        categoryId: _categoryId,
      );
      if (!mounted) return;
      setState(() {
        _products = res.data;
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
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
                      hintText: 'Search shop',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
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
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(child: Center(child: Text(_error!)))
          else if (_products.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('No shop products yet.')))
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 200,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = _products[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ShopProductDetailScreen(productId: p.id),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: p.images.isNotEmpty
                                  ? Image.network(p.images.first, fit: BoxFit.cover)
                                  : ColoredBox(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.store),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(p.priceLabel,
                                      style: const TextStyle(
                                          color: Color(0xFF702078),
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _products.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}