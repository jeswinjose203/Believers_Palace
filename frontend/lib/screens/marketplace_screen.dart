import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import 'community_ads_browse_screen.dart';
import 'marketplace_admin_screen.dart';
import 'my_community_ads_screen.dart';
import 'shop_products_browse_screen.dart';

const _kPurple = Color(0xFF702078);

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _isAdmin {
    final role = ref.watch(authProvider.select((s) => s.user?.role));
    return role == 'church_admin' || role == 'super_admin';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabs,
                labelColor: _kPurple,
                indicatorColor: _kPurple,
                tabs: const [
                  Tab(text: 'Community'),
                  Tab(text: 'Shop'),
                ],
              ),
            ),
            IconButton(
              tooltip: 'My listings',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MyCommunityAdsScreen()),
                );
              },
            ),
            if (_isAdmin)
              IconButton(
                tooltip: 'Manage marketplace',
                icon: const Icon(Icons.admin_panel_settings_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MarketplaceAdminScreen()),
                  );
                },
              ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              CommunityAdsBrowseScreen(),
              ShopProductsBrowseScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
