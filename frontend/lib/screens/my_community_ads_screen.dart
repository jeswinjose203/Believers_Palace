import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import 'community_ad_detail_screen.dart';
import 'community_ad_form_screen.dart';

class MyCommunityAdsScreen extends ConsumerStatefulWidget {
  const MyCommunityAdsScreen({super.key});

  @override
  ConsumerState<MyCommunityAdsScreen> createState() => _MyCommunityAdsScreenState();
}

class _MyCommunityAdsScreenState extends ConsumerState<MyCommunityAdsScreen> {
  List<CommunityAd> _ads = [];
  bool _loading = true;
  String? _error;

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
      final res = await ref.read(apiServiceProvider).listMyCommunityAds();
      if (!mounted) return;
      setState(() {
        _ads = res.data;
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

  Future<void> _edit(CommunityAd ad) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CommunityAdFormScreen(existing: ad)),
    );
    if (updated == true) _load();
  }

  Future<void> _delete(CommunityAd ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove listing?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiServiceProvider).deleteCommunityAd(ad.id);
    _load();
  }

  Future<void> _markSold(CommunityAd ad) async {
    await ref.read(apiServiceProvider).markCommunityAdSold(ad.id);
    _load();
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending_approval':
        return 'Pending approval';
      case 'approved':
        return 'Published';
      case 'rejected':
        return 'Rejected';
      case 'sold':
        return 'Sold';
      case 'removed':
        return 'Removed';
      default:
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My listings')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const CommunityAdFormScreen()),
          );
          if (created == true) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _ads.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 48),
                            Center(child: Text('You have not posted any listings yet.')),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _ads.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final ad = _ads[i];
                            return ListTile(
                              title: Text(ad.title),
                              subtitle: Text('${_statusLabel(ad.status)} · ${ad.priceLabel}'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CommunityAdDetailScreen(adId: ad.id),
                                  ),
                                );
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'edit':
                                      _edit(ad);
                                      break;
                                    case 'sold':
                                      _markSold(ad);
                                      break;
                                    case 'delete':
                                      _delete(ad);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (ad.status != 'sold' && ad.status != 'removed')
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  if (ad.status == 'approved')
                                    const PopupMenuItem(value: 'sold', child: Text('Mark sold')),
                                  const PopupMenuItem(value: 'delete', child: Text('Remove')),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}