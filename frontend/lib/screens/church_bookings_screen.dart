import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Shows the requester's profile in a bottom sheet with quick contact links.
  void _showRequester(BookingRequester u) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage:
                      (u.profilePic != null && u.profilePic!.isNotEmpty)
                          ? NetworkImage(u.profilePic!)
                          : null,
                  child: (u.profilePic == null || u.profilePic!.isEmpty)
                      ? const Icon(Icons.person, size: 28)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.name.isEmpty ? 'Unknown user' : u.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const Text('Booking requester',
                          style: TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (u.email.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined),
                title: Text(u.email),
                onTap: () => _launch('mailto:${u.email}'),
              ),
            if ((u.phone ?? '').isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_outlined),
                title: Text(u.phone!),
                onTap: () => _launch('tel:${u.phone}'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(String uri) async {
    final parsed = Uri.parse(uri);
    if (await canLaunchUrl(parsed)) {
      await launchUrl(parsed);
    } else {
      _show('Could not open $uri');
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
                final requester = b.user;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Requester row: avatar + name/email, tappable to view
                        // the full profile.
                        InkWell(
                          onTap: requester == null
                              ? null
                              : () => _showRequester(requester),
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundImage: (requester?.profilePic != null &&
                                        requester!.profilePic!.isNotEmpty)
                                    ? NetworkImage(requester.profilePic!)
                                    : null,
                                child: (requester?.profilePic == null ||
                                        requester!.profilePic!.isEmpty)
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      requester?.name ?? 'Unknown user',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    if ((requester?.email ?? '').isNotEmpty)
                                      Text(
                                        requester!.email,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54),
                                      ),
                                  ],
                                ),
                              ),
                              if (requester != null)
                                const Icon(Icons.chevron_right,
                                    color: Colors.black38),
                            ],
                          ),
                        ),
                        const Divider(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.event,
                                size: 16, color: Colors.black54),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${fmt.format(b.startDate.toLocal())} → '
                                '${fmt.format(b.endDate.toLocal())}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Purpose: ${b.purpose ?? "-"}',
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _StatusChip(status: b.status),
                            const Spacer(),
                            if (pending) ...[
                              TextButton.icon(
                                icon: const Icon(Icons.check_circle_outline,
                                    color: Colors.green),
                                label: const Text('Accept',
                                    style: TextStyle(color: Colors.green)),
                                onPressed: () => _setStatus(b, 'approved'),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.cancel_outlined,
                                    color: Colors.red),
                                label: const Text('Decline',
                                    style: TextStyle(color: Colors.red)),
                                onPressed: () => _setStatus(b, 'rejected'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
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

/// A small coloured chip that reflects a booking's status.
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'approved':
        bg = const Color(0xFFE6F4EA);
        fg = const Color(0xFF1E7E34);
        break;
      case 'rejected':
        bg = const Color(0xFFFDE8E8);
        fg = const Color(0xFFC0392B);
        break;
      case 'cancelled':
        bg = const Color(0xFFEDEDED);
        fg = Colors.black54;
        break;
      case 'pending':
      default:
        bg = const Color(0xFFFFF4E0);
        fg = const Color(0xFFB8860B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

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
