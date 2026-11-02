import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// Admin view of all bookings for a church, with approve/reject controls.
class ChurchBookingsScreen extends ConsumerStatefulWidget {
  final String churchId;
  final String churchName;

  const ChurchBookingsScreen({
    super.key,
    required this.churchId,
    required this.churchName,
  });

  @override
  ConsumerState<ChurchBookingsScreen> createState() =>
      _ChurchBookingsScreenState();
}

class _ChurchBookingsScreenState extends ConsumerState<ChurchBookingsScreen> {
  Future<PaginatedResponse<Booking>>? _future;
  String? _statusFilter;

  Future<PaginatedResponse<Booking>> _load() => ref
      .read(apiServiceProvider)
      .listChurchBookings(widget.churchId, status: _statusFilter, limit: 100);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setStatus(Booking b, String status) async {
    final notes = await showDialog<String?>(
      context: context,
      builder: (context) => _NotesDialog(
        title: status == 'approved' ? 'Approve booking' : 'Reject booking',
      ),
    );
    // A null result means the dialog was dismissed; proceed only on confirm.
    if (notes == _cancelSentinel) return;
    try {
      await ref.read(apiServiceProvider).updateBookingStatus(
            b.id,
            status,
            (notes == null || notes.isEmpty) ? null : notes,
          );
      _show('Booking $status');
      _refresh();
    } catch (e) {
      _show(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.churchName} · Bookings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: DropdownButtonFormField<String?>(
              value: _statusFilter,
              decoration: const InputDecoration(
                labelText: 'Filter by status',
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('All')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _refresh();
              },
            ),
          ),
        ),
      ),
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
            return const Center(child: Text('No bookings.'));
          }
          final fmt = DateFormat.yMd().add_jm();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: bookings.length,
              itemBuilder: (context, i) {
                final b = bookings[i];
                final pending = b.status == 'pending';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(fmt.format(b.startDate.toLocal())),
                    subtitle: Text(
                      'Purpose: ${b.purpose ?? "-"}\nStatus: ${b.status}',
                    ),
                    isThreeLine: true,
                    trailing: pending
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline,
                                    color: Colors.green),
                                tooltip: 'Approve',
                                onPressed: () => _setStatus(b, 'approved'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel_outlined,
                                    color: Colors.red),
                                tooltip: 'Reject',
                                onPressed: () => _setStatus(b, 'rejected'),
                              ),
                            ],
                          )
                        : Chip(label: Text(b.status)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Sentinel distinguishing a cancelled dialog from an empty-notes confirmation.
const String _cancelSentinel = '\u0000__cancel__';

class _NotesDialog extends StatelessWidget {
  final String title;

  _NotesDialog({required this.title});

  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Admin notes (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_cancelSentinel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
