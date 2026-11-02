import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'church_detail_screen.dart';

class ChurchesScreen extends ConsumerStatefulWidget {
  const ChurchesScreen({super.key});

  @override
  ConsumerState<ChurchesScreen> createState() => _ChurchesScreenState();
}

class _ChurchesScreenState extends ConsumerState<ChurchesScreen> {
  final _search = TextEditingController();
  Future<PaginatedResponse<Church>>? _future;

  Future<PaginatedResponse<Church>> _load() => ref
      .read(apiServiceProvider)
      .listChurches(search: _search.text, limit: 50);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Churches')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search churches',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _refresh,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
          Expanded(
            child: FutureBuilder<PaginatedResponse<Church>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Error: ${snapshot.error}'),
                    ),
                  );
                }
                final churches = snapshot.data?.data ?? [];
                if (churches.isEmpty) {
                  return const Center(child: Text('No churches found.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: churches.length,
                    itemBuilder: (context, i) {
                      final c = churches[i];
                      return ListTile(
                        leading: c.logo != null
                            ? CircleAvatar(backgroundImage: NetworkImage(c.logo!))
                            : const CircleAvatar(child: Icon(Icons.church)),
                        title: Text(c.name),
                        subtitle: Text(c.address ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChurchDetailScreen(church: c),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
