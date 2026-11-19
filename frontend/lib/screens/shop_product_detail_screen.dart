import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/marketplace_models.dart';
import '../services/api_service.dart';

class ShopProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ShopProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ShopProductDetailScreen> createState() =>
      _ShopProductDetailScreenState();
}

class _ShopProductDetailScreenState extends ConsumerState<ShopProductDetailScreen> {
  ShopProduct? _product;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(apiServiceProvider).getShopProduct(widget.productId);
      if (!mounted) return;
      setState(() {
        _product = p;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Shop item')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_product!.images.isNotEmpty)
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.network(_product!.images.first, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 12),
                    Text(_product!.title, style: Theme.of(context).textTheme.headlineSmall),
                    Text(_product!.priceLabel,
                        style: const TextStyle(fontSize: 20, color: Color(0xFF702078))),
                    if (_product!.categoryName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Category: ${_product!.categoryName}'),
                      ),
                    const SizedBox(height: 12),
                    Text(_product!.description),
                    const SizedBox(height: 16),
                    const Text(
                      'Official church shop catalog item. Contact your church administrator to purchase.',
                    ),
                  ],
                ),
    );
  }
}