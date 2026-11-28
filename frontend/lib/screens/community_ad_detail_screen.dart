import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_locale.dart';
import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import '../widgets/user_error.dart';

class CommunityAdDetailScreen extends ConsumerStatefulWidget {
  final String adId;

  const CommunityAdDetailScreen({super.key, required this.adId});

  @override
  ConsumerState<CommunityAdDetailScreen> createState() =>
      _CommunityAdDetailScreenState();
}

class _CommunityAdDetailScreenState extends ConsumerState<CommunityAdDetailScreen> {
  CommunityAd? _ad;
  bool _loading = true;
  String? _error;
  int _imageIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ad = await ref.read(apiServiceProvider).getCommunityAd(widget.adId);
      if (!mounted) return;
      setState(() {
        _ad = ad;
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

  Future<void> _contact(String uri) async {
    final link = Uri.parse(uri);
    if (!await launchUrl(link)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Could not open {0}', [uri]))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Listing'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(context.tr(_error!)))
              : _buildBody(_ad!),
    );
  }

  Widget _buildBody(CommunityAd ad) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (ad.images.isNotEmpty)
          Column(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(ad.images[_imageIndex], fit: BoxFit.cover),
              ),
              if (ad.images.length > 1)
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => setState(() => _imageIndex = i),
                      child: Image.network(ad.images[i], width: 56, height: 56, fit: BoxFit.cover),
                    ),
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemCount: ad.images.length,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Text(ad.title, style: Theme.of(context).textTheme.headlineSmall),
        Text(ad.priceLabel,
            style: const TextStyle(fontSize: 20, color: Color(0xFF702078))),
        if (ad.isSold)
          Chip(label: Text(context.tr('Sold'))),
        const SizedBox(height: 8),
        Text(ad.description),
        const SizedBox(height: 12),
        _row(Icons.category, ad.categoryName ?? 'Category'),
        _row(Icons.place, ad.location),
        _row(Icons.sell, ad.condition == 'new' ? 'New' : 'Used'),
        if (ad.seller != null) ...[
          const SizedBox(height: 16),
          Text(context.tr('Seller'), style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            leading: CircleAvatar(
              backgroundImage: ad.seller!.profilePic != null
                  ? NetworkImage(ad.seller!.profilePic!)
                  : null,
              child: ad.seller!.profilePic == null ? const Icon(Icons.person) : null,
            ),
            title: Text(ad.seller!.name),
          ),
        ],
        const SizedBox(height: 8),
        Text(context.tr('Contact'), style: Theme.of(context).textTheme.titleMedium),
        if (ad.contactPhone != null)
          ListTile(
            leading: const Icon(Icons.phone),
            title: Text(ad.contactPhone!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _contact('tel:${ad.contactPhone}'),
          ),
        if (ad.contactEmail != null)
          ListTile(
            leading: const Icon(Icons.email),
            title: Text(ad.contactEmail!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _contact('mailto:${ad.contactEmail}'),
          ),
      ],
    );
  }

  Widget _row(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}