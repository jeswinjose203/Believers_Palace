import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> {
  Future<PaginatedResponse<Booking>>? _future;

  Future<PaginatedResponse<Booking>> _load() =>
      ref.read(apiServiceProvider).listMyBookings(limit: 50);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _cancel(Booking booking) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _CancelDialog(),
    );
    if (!mounted) return;
    try {
      await ref.read(apiServiceProvider).cancelBooking(booking.id, reason: reason);
      _show('Booking cancelled');
      _refresh();
    } catch (e) {
      _show(e.toString(), isError: true);
    }
  }

  void _show(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: FutureBuilder<PaginatedResponse<Booking>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final bookings = snapshot.data?.data ?? [];
          if (bookings.isEmpty) {
            return const Center(child: Text('No bookings yet.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: bookings.length,
              itemBuilder: (context, i) {
                final b = bookings[i];
                final fmt = DateFormat.yMd().add_jm();
                return ListTile(
                  title: Text('${fmt.format(b.startDate.toLocal())}'),
                  subtitle: Text('Purpose: ${b.purpose ?? "-"}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(b.status),
                        backgroundColor: _statusColor(b.status),
                      ),
                      if (b.status == 'pending' || b.status == 'approved')
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () => _cancel(b),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green.shade100;
      case 'rejected':
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade200;
    }
  }
}

class _CancelDialog extends StatelessWidget {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel booking'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Reason (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.isEmpty ? null : _controller.text),
          child: const Text('Cancel booking'),
        ),
      ],
    );
  }
}
