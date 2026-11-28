import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../models/marketplace_models.dart';
import '../services/api_service.dart';
import '../widgets/multi_image_picker_field.dart';
import '../widgets/user_error.dart';

class MarketplaceAdminScreen extends StatefulWidget {
  const MarketplaceAdminScreen({super.key});

  @override
  State<MarketplaceAdminScreen> createState() => _MarketplaceAdminScreenState();
}

class _MarketplaceAdminScreenState extends State<MarketplaceAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Manage marketplace')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: context.tr('Pending ads')),
            Tab(text: context.tr('Categories')),
            Tab(text: context.tr('Shop')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _PendingAdsTab(),
          _CategoriesTab(),
          _ShopAdminTab(),
        ],
      ),
    );
  }
}

class _PendingAdsTab extends ConsumerStatefulWidget {
  const _PendingAdsTab();

  @override
  ConsumerState<_PendingAdsTab> createState() => _PendingAdsTabState();
}

class _PendingAdsTabState extends ConsumerState<_PendingAdsTab> {
  List<CommunityAd> _ads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ref.read(apiServiceProvider).listCommunityAdsAdmin();
    if (!mounted) return;
    setState(() {
      _ads = res.data;
      _loading = false;
    });
  }

  Future<void> _approve(CommunityAd ad) async {
    await ref.read(apiServiceProvider).approveCommunityAd(ad.id);
    _load();
  }

  Future<void> _reject(CommunityAd ad) async {
    await ref.read(apiServiceProvider).rejectCommunityAd(ad.id);
    _load();
  }

  Future<void> _remove(CommunityAd ad) async {
    await ref.read(apiServiceProvider).deleteCommunityAd(ad.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_ads.isEmpty) return Center(child: Text(context.tr('No pending advertisements.')));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _ads.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final ad = _ads[i];
          return ListTile(
            title: Text(ad.title),
            subtitle: Text('${ad.priceLabel} · ${ad.location}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: context.tr('Approve'),
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _approve(ad),
                ),
                IconButton(
                  tooltip: context.tr('Reject'),
                  icon: const Icon(Icons.close, color: Colors.orange),
                  onPressed: () => _reject(ad),
                ),
                IconButton(
                  tooltip: context.tr('Remove'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(ad),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoriesTab extends ConsumerStatefulWidget {
  const _CategoriesTab();

  @override
  ConsumerState<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<_CategoriesTab> {
  String _scope = 'community';
  List<MarketplaceCategory> _cats = [];
  bool _loading = true;

  Future<void> _load() async {
    setState(() => _loading = true);
    final list =
        await ref.read(apiServiceProvider).listMarketplaceCategories(_scope, all: true);
    if (!mounted) return;
    setState(() {
      _cats = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = await _prompt(context, 'Category name');
    if (name == null || name.isEmpty) return;
    await ref.read(apiServiceProvider).createMarketplaceCategory(_scope, name: name);
    _load();
  }

  Future<void> _rename(MarketplaceCategory c) async {
    final name = await _prompt(context, 'Rename category', initial: c.name);
    if (name == null || name.isEmpty) return;
    await ref.read(apiServiceProvider).updateMarketplaceCategory(c.id, name: name, active: c.active);
    _load();
  }

  Future<void> _toggle(MarketplaceCategory c) async {
    await ref
        .read(apiServiceProvider)
        .updateMarketplaceCategory(c.id, name: c.name, active: !c.active);
    _load();
  }

  Future<void> _delete(MarketplaceCategory c) async {
    try {
      await ref.read(apiServiceProvider).deleteMarketplaceCategory(c.id);
      _load();
    } catch (e) {
      if (mounted) {
        showUserError(context, e);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'community', label: Text(context.tr('Community'))),
              ButtonSegment(value: 'shop', label: Text(context.tr('Shop'))),
            ],
            selected: {_scope},
            onSelectionChanged: (s) {
              setState(() => _scope = s.first);
              _load();
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    ..._cats.map(
                      (c) => ListTile(
                        title: Text(c.name),
                        subtitle: Text(c.active ? context.tr('Active') : context.tr('Inactive')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (a) {
                            switch (a) {
                              case 'rename':
                                _rename(c);
                                break;
                              case 'toggle':
                                _toggle(c);
                                break;
                              case 'delete':
                                _delete(c);
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'rename', child: Text(context.tr('Rename'))),
                            PopupMenuItem(value: 'toggle', child: Text(context.tr('Toggle active'))),
                            PopupMenuItem(value: 'delete', child: Text(context.tr('Delete'))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(context.tr('Add category')),
          ),
        ),
      ],
    );
  }
}

class _ShopAdminTab extends ConsumerStatefulWidget {
  const _ShopAdminTab();

  @override
  ConsumerState<_ShopAdminTab> createState() => _ShopAdminTabState();
}

class _ShopAdminTabState extends ConsumerState<_ShopAdminTab> {
  List<ShopProduct> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ref.read(apiServiceProvider).listShopProductsAdmin();
    if (!mounted) return;
    setState(() {
      _products = res.data;
      _loading = false;
    });
  }

  Future<void> _openEditor({ShopProduct? existing}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ShopProductEditor(existing: existing)),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(ShopProduct p) async {
    await ref.read(apiServiceProvider).deleteShopProduct(p.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = _products[i];
                return ListTile(
                  title: Text(p.title),
                  subtitle: Text('${p.priceLabel} · ${p.active ? 'Active' : 'Inactive'}'),
                  onTap: () => _openEditor(existing: p),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(p),
                  ),
                );
              },
            ),
    );
  }
}

class _ShopProductEditor extends ConsumerStatefulWidget {
  final ShopProduct? existing;

  const _ShopProductEditor({this.existing});

  @override
  ConsumerState<_ShopProductEditor> createState() => _ShopProductEditorState();
}

class _ShopProductEditorState extends ConsumerState<_ShopProductEditor> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  List<String> _images = [];
  String? _categoryId;
  bool _active = true;
  List<MarketplaceCategory> _categories = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title.text = e?.title ?? '';
    _description.text = e?.description ?? '';
    _price.text = e != null ? (e.priceCents / 100).toStringAsFixed(2) : '';
    _images = List.from(e?.images ?? []);
    _categoryId = e?.categoryId;
    _active = e?.active ?? true;
    ref.read(apiServiceProvider).listMarketplaceCategories('shop', all: true).then((cats) {
      if (mounted) setState(() => _categories = cats);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_price.text.trim());
    if (v == null || v <= 0) return;
    setState(() => _saving = true);
    final body = {
      if (_categoryId != null) 'categoryId': _categoryId,
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'images': _images,
      'priceCents': (v * 100).round(),
      'active': _active,
    };
    final api = ref.read(apiServiceProvider);
    try {
      if (widget.existing == null) {
        await api.createShopProduct(body);
      } else {
        await api.updateShopProduct(widget.existing!.id, body);
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? context.tr('New shop product') : context.tr('Edit product'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: InputDecoration(labelText: context.tr('Title'))),
          TextField(
            controller: _description,
            decoration: InputDecoration(labelText: context.tr('Description')),
            maxLines: 3,
          ),
          MultiImagePickerField(
            label: context.tr('Photos'),
            initialUrls: _images,
            onChanged: (u) => setState(() => _images = u),
          ),
          DropdownButtonFormField<String?>(
            value: _categoryId,
            decoration: InputDecoration(labelText: context.tr('Category')),
            items: [
              DropdownMenuItem(value: null, child: Text(context.tr('None'))),
              ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          TextField(
            controller: _price,
            decoration: InputDecoration(labelText: context.tr('Price (USD)')),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          SwitchListTile(
            title: Text(context.tr('Active')),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CircularProgressIndicator() : Text(context.tr('Save')),
          ),
        ],
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, {String initial = ''}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(ctx.tr('OK'))),
      ],
    ),
  );
  return result;
}