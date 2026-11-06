import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// Admin view of everyone registered for an event: shows the total count and
/// the list of attendees. The backend restricts this to staff of the event's
/// church (and super admins).
class EventRegistrationsScreen extends ConsumerStatefulWidget {
  final Event event;

  const EventRegistrationsScreen({super.key, required this.event});

  @override
  ConsumerState<EventRegistrationsScreen> createState() =>
      _EventRegistrationsScreenState();
}

class _EventRegistrationsScreenState
    extends ConsumerState<EventRegistrationsScreen> {
  late Future<PaginatedResponse<EventRegistration>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PaginatedResponse<EventRegistration>> _load() => ref
      .read(apiServiceProvider)
      .listEventRegistrations(widget.event.id, limit: 100);

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.MMMd().add_jm();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.event.title} · Registrations')),
      body: FutureBuilder<PaginatedResponse<EventRegistration>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final res = snap.data!;
          final total = res.pagination.total;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text('$total registered',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: widget.event.capacity != null
                      ? Text('Capacity: ${widget.event.capacity}')
                      : null,
                ),
                const Divider(height: 1),
                if (res.data.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No one has registered yet.')),
                  ),
                for (final r in res.data)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(
                      (r.attendeeName ?? '').isNotEmpty
                          ? r.attendeeName!
                          : 'Unnamed attendee',
                    ),
                    subtitle: Text([
                      if ((r.attendeeEmail ?? '').isNotEmpty) r.attendeeEmail!,
                      if ((r.attendeePhone ?? '').isNotEmpty) r.attendeePhone!,
                      if ((r.notes ?? '').isNotEmpty) 'Note: ${r.notes}',
                    ].join('\n')),
                    isThreeLine: [r.attendeeEmail, r.attendeePhone, r.notes]
                            .where((s) => (s ?? '').isNotEmpty)
                            .length >
                        1,
                    trailing: r.createdAt != null
                        ? Text(fmt.format(r.createdAt!.toLocal()),
                            style: Theme.of(context).textTheme.labelSmall)
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
