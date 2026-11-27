import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_locale.dart';
import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'church_detail_screen.dart';

const _ink = Color(0xFF302039);
const _purple = Color(0xFF51205D);
const _plum = Color(0xFF7A247E);
const _pale = Color(0xFFF8F5FA);

/// Discovery home for members, styled around browsing churches near them.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();
  Future<PaginatedResponse<Church>>? _future;
  Timer? _searchDebounce;

  Future<PaginatedResponse<Church>> _load() =>
      ref.read(apiServiceProvider).listChurches(search: _search.text, limit: 50);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChurches(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _future = _load());
    });
  }

  void _submitSearch(String _) {
    _searchDebounce?.cancel();
    setState(() => _future = _load());
  }

  Future<void> _setMyChurch(Church church) async {
    try {
      await ref.read(authProvider.notifier).updateProfile({'churchId': church.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('{0} selected', [church.name]))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _openChurch(Church church) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChurchDetailScreen(church: church),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final selectedChurchId = ref.watch(authProvider.select((state) => state.user?.churchId));
    return Scaffold(
      backgroundColor: const Color(0xFFFCFAFD),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('DISCOVER'), style: const TextStyle(fontSize: 9, letterSpacing: 1.6, color: Color(0xFF9A8A9D), fontWeight: FontWeight.w700)),
                              const SizedBox(height: 5),
                              Text(context.tr('Churches for you'), style: const TextStyle(color: _plum, fontSize: 20, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _search,
                      onChanged: _searchChurches,
                      onSubmitted: _submitSearch,
                      decoration: InputDecoration(
                        hintText: context.tr('Search churches or locations'),
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9D93A2)),
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9D93A2)),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: context.tr('Clear search'),
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  _submitSearch('');
                                },
                              ),
                        filled: true,
                        fillColor: const Color(0xFFF4F0F6),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<PaginatedResponse<Church>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()));
                        }
                        if (snapshot.hasError) {
                          return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(context.tr('Could not load churches: {0}', [snapshot.error]))));
                        }
                        final churches = snapshot.data?.data ?? const <Church>[];
                        if (churches.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(context.tr('No churches found.'))));
                        return Column(children: [
                          for (var i = 0; i < churches.length; i++) ...[
                            _ChurchCard(
                              church: churches[i],
                              featured: i == 0,
                              isMyChurch: selectedChurchId == churches[i].id,
                              onTap: () => _openChurch(churches[i]),
                              onSetMyChurch: () => _setMyChurch(churches[i]),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _communityBanner(context),
                        ]);
                      },
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChurchCard extends StatelessWidget {
  final Church church;
  final bool featured;
  final bool isMyChurch;
  final VoidCallback onTap;
  final VoidCallback onSetMyChurch;
  const _ChurchCard({required this.church, required this.featured, required this.isMyChurch, required this.onTap, required this.onSetMyChurch});

  @override
  Widget build(BuildContext context) {
    final photo = church.images.isNotEmpty ? church.images.first : church.logo;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .07), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 105, width: double.infinity, child: Stack(fit: StackFit.expand, children: [
          if (photo != null && photo.isNotEmpty) Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _churchPlaceholder()) else _churchPlaceholder(),
          if (featured) Positioned(right: 9, top: 9, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFFCE6F5), borderRadius: BorderRadius.circular(20)), child: Text(context.tr('Great match'), style: const TextStyle(color: _plum, fontSize: 7, fontWeight: FontWeight.w700)))),
          Positioned(left: 8, bottom: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .53), borderRadius: BorderRadius.circular(12)), child: Text('◉  4.8 mi', style: const TextStyle(color: Colors.white, fontSize: 7)))),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(9, 7, 9, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(church.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _plum, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: featured ? 'serif' : null)),
          Text(church.address ?? context.tr('Community Church'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9C929F), fontSize: 7)),
          const SizedBox(height: 6),
          const Divider(height: 1, color: Color(0xFFF0EDF1)),
          const SizedBox(height: 6),
          const Row(children: [Icon(Icons.schedule, color: _plum, size: 10), SizedBox(width: 5), Text('Sunday · 8:30 AM', style: TextStyle(color: _ink, fontSize: 7))]),
          const SizedBox(height: 7),
          SizedBox(width: double.infinity, height: 30, child: FilledButton.icon(onPressed: onTap, icon: const Icon(Icons.arrow_forward, size: 12), label: Text(context.tr('View church'), style: const TextStyle(fontSize: 9)), style: FilledButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)), padding: EdgeInsets.zero))),
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, height: 30, child: OutlinedButton.icon(onPressed: isMyChurch ? null : onSetMyChurch, icon: Icon(isMyChurch ? Icons.check_circle_outline : Icons.favorite_border, size: 13), label: Text(context.tr(isMyChurch ? 'My church' : 'Set my church'), style: const TextStyle(fontSize: 9)), style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: Color(0xFFE3D7E7)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)), padding: EdgeInsets.zero))),
        ])),
      ]),
    );
  }
}

Widget _churchPlaceholder() => Container(color: const Color(0xFFE9DDED), child: const Center(child: Icon(Icons.church_outlined, color: _plum, size: 42)));

Widget _communityBanner(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF7EAF7), borderRadius: BorderRadius.circular(14)), child: Text(context.tr('NEW TO THE COMMUNITY?\nFind your place and grow together.'), style: const TextStyle(color: _purple, fontSize: 11, height: 1.5, fontWeight: FontWeight.w600)));
