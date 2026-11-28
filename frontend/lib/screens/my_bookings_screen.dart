import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_locale.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/user_error.dart';

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
      if (mounted) _show(context.tr('Booking cancelled'));
      _refresh();
    } catch (e) {
      if (mounted) showUserError(context, e);
    }
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('My Bookings'))),
      body: FutureBuilder<PaginatedResponse<Booking>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(context.tr(userErrorMessage(snapshot.error))));
          }
          final bookings = snapshot.data?.data ?? [];
          if (bookings.isEmpty) {
            return Center(child: Text(context.tr('No bookings yet.')));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: bookings.length,
              itemBuilder: (context, i) {
                final b = bookings[i];
                final fmt = DateFormat.yMd(context.dateLocale).add_jm();
                return ListTile(
                  title: Text('${fmt.format(b.startDate.toLocal())}'),
                  subtitle: Text(context.tr('Purpose: {0}', [b.purpose ?? "-"])),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(context.tr(b.status)),
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
      title: Text(context.tr('Cancel booking')),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(labelText: context.tr('Reason (optional)')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Keep')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.isEmpty ? null : _controller.text),
          child: Text(context.tr('Cancel booking')),
        ),
      ],
    );
  }
}
