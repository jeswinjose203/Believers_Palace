import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import '../widgets/user_error.dart';

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
        _error = userErrorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Shop item'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(context.tr(_error!)))
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
                        child: Text(context.tr('Category: {0}', [_product!.categoryName])),
                      ),
                    const SizedBox(height: 12),
                    Text(_product!.description),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('Official church shop catalog item. Contact your church administrator to purchase.'),
                    ),
                  ],
                ),
    );
  }
}