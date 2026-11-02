import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ChurchDetailScreen extends ConsumerStatefulWidget {
  final Church church;

  const ChurchDetailScreen({super.key, required this.church});

  @override
  ConsumerState<ChurchDetailScreen> createState() => _ChurchDetailScreenState();
}

class _ChurchDetailScreenState extends ConsumerState<ChurchDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.role == 'church_admin' || user?.role == 'super_admin';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.church.name),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Announcements'),
            Tab(text: 'Halls'),
            Tab(text: 'Events'),
            Tab(text: 'Cemetery Plots'),
            Tab(text: 'Cemetery Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AnnouncementsTab(churchId: widget.church.id),
          _HallsTab(
            churchId: widget.church.id,
            onBook: (hall) => _showBookingDialog(hall),
          ),
          _EventsTab(
            churchId: widget.church.id,
            onRegister: (event) => _showRegisterDialog(event),
          ),
          _CemeteryPlotsTab(churchId: widget.church.id),
          _CemeteryRequestsTab(
            churchId: widget.church.id,
            isAdmin: isAdmin,
            onNew: () => _showCemeteryRequestDialog(),
          ),
        ],
      ),
    );
  }

  Future<void> _showBookingDialog(Hall hall) async {
    final start = DateTime.now();
    final end = start.add(const Duration(hours: 2));
    final purpose = TextEditingController();
    final notes = TextEditingController();
    DateTime? chosenStart = start;
    DateTime? chosenEnd = end;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Book ${hall.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DateTimeField(
                label: 'Start',
                initial: chosenStart!,
                onPicked: (d) => chosenStart = d,
              ),
              _DateTimeField(
                label: 'End',
                initial: chosenEnd!,
                onPicked: (d) => chosenEnd = d,
              ),
              TextField(
                controller: purpose,
                decoration: const InputDecoration(labelText: 'Purpose'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (chosenStart == null || chosenEnd == null) return;
              try {
                await ref.read(apiServiceProvider).createBooking(
                  widget.church.id,
                  {
                    'hallId': hall.id,
                    'startDate': chosenStart!.toIso8601String(),
                    'endDate': chosenEnd!.toIso8601String(),
                    'purpose': purpose.text.isEmpty ? null : purpose.text,
                    'notes': notes.text.isEmpty ? null : notes.text,
                  },
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                  _showSuccess('Booking requested');
                }
              } catch (e) {
                _showError(e.toString());
              }
            },
            child: const Text('Book'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRegisterDialog(Event event) async {
    final user = ref.read(authProvider).user;
    final name = TextEditingController(text: user?.name);
    final email = TextEditingController(text: user?.email);
    final phone = TextEditingController(text: user?.phone ?? '');
    final notes = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Register for ${event.title}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).registerForEvent(
                  event.id,
                  {
                    'attendeeName': name.text.isEmpty ? null : name.text,
                    'attendeeEmail': email.text.isEmpty ? null : email.text,
                    'attendeePhone': phone.text.isEmpty ? null : phone.text,
                    'notes': notes.text.isEmpty ? null : notes.text,
                  },
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                  _showSuccess('Registered for event');
                }
              } catch (e) {
                _showError(e.toString());
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCemeteryRequestDialog() async {
    String type = 'burial';
    final fullName = TextEditingController();
    final contactPhone = TextEditingController();
    final contactEmail = TextEditingController();
    final deceasedName = TextEditingController();
    final plotId = TextEditingController();
    final description = TextEditingController();
    final notes = TextEditingController();
    DateTime? requestedDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Cemetery Request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    'burial',
                    'plot_reservation',
                    'grave_maintenance',
                    'memorial_service',
                    'other',
                  ]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => type = v!),
                ),
                TextField(
                  controller: fullName,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                ),
                TextField(
                  controller: contactPhone,
                  decoration: const InputDecoration(labelText: 'Contact phone'),
                ),
                TextField(
                  controller: contactEmail,
                  decoration: const InputDecoration(labelText: 'Contact email'),
                ),
                TextField(
                  controller: deceasedName,
                  decoration: const InputDecoration(labelText: 'Deceased name'),
                ),
                _DateTimeField(
                  label: 'Requested date',
                  initial: DateTime.now(),
                  onPicked: (d) => requestedDate = d,
                ),
                TextField(
                  controller: plotId,
                  decoration: const InputDecoration(labelText: 'Plot ID (optional)'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description *'),
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(apiServiceProvider).createCemeteryRequest(
                    widget.church.id,
                    {
                      'type': type,
                      'fullName': fullName.text,
                      'contactPhone': contactPhone.text.isEmpty ? null : contactPhone.text,
                      'contactEmail': contactEmail.text.isEmpty ? null : contactEmail.text,
                      'deceasedName': deceasedName.text.isEmpty ? null : deceasedName.text,
                      'requestedDate': requestedDate?.toIso8601String(),
                      'plotId': plotId.text.isEmpty ? null : plotId.text,
                      'description': description.text,
                      'notes': notes.text.isEmpty ? null : notes.text,
                    },
                  );
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _showSuccess('Request submitted');
                  }
                } catch (e) {
                  _showError(e.toString());
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeField extends StatefulWidget {
  final String label;
  final DateTime initial;
  final ValueChanged<DateTime?> onPicked;

  const _DateTimeField({
    required this.label,
    required this.initial,
    required this.onPicked,
  });

  @override
  State<_DateTimeField> createState() => _DateTimeFieldState();
}

class _DateTimeFieldState extends State<_DateTimeField> {
  late DateTime _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  Future<void> _pick() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_value),
    );
    if (time == null) return;
    setState(() {
      _value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    widget.onPicked(_value);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.label),
      subtitle: Text(_value.toLocal().toString()),
      trailing: const Icon(Icons.calendar_today),
      onTap: _pick,
    );
  }
}

class _AnnouncementsTab extends ConsumerWidget {
  final String churchId;

  const _AnnouncementsTab({required this.churchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedList<Announcement>(
      future: ref.read(apiServiceProvider).listAnnouncements(churchId, limit: 50),
      itemBuilder: (a) => ListTile(
        title: Text(a.title),
        subtitle: Text(a.content),
        trailing: a.publishedAt != null
            ? Text(_shortDate(a.publishedAt!))
            : null,
      ),
    );
  }
}

class _HallsTab extends ConsumerWidget {
  final String churchId;
  final ValueChanged<Hall> onBook;

  const _HallsTab({required this.churchId, required this.onBook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedList<Hall>(
      future: ref.read(apiServiceProvider).listHalls(churchId, limit: 50),
      itemBuilder: (h) => ListTile(
        title: Text(h.name),
        subtitle: Text(
          [if (h.location != null) h.location, if (h.capacity != null) 'Capacity: ${h.capacity}']
              .where((s) => s != null)
              .join(' · '),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: () => onBook(h),
        ),
      ),
    );
  }
}

class _EventsTab extends ConsumerWidget {
  final String churchId;
  final ValueChanged<Event> onRegister;

  const _EventsTab({required this.churchId, required this.onRegister});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedList<Event>(
      future: ref.read(apiServiceProvider).listEvents(churchId, limit: 50),
      itemBuilder: (e) => ListTile(
        title: Text(e.title),
        subtitle: Text(
          '${_shortDate(e.startDate)}${e.location != null ? ' · ${e.location}' : ''}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.how_to_reg),
          onPressed: () => onRegister(e),
        ),
      ),
    );
  }
}

class _CemeteryPlotsTab extends ConsumerWidget {
  final String churchId;

  const _CemeteryPlotsTab({required this.churchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedList<CemeteryPlot>(
      future: ref.read(apiServiceProvider).listCemeteryPlots(churchId, limit: 50),
      itemBuilder: (p) => ListTile(
        title: Text('Plot ${p.plotNumber}'),
        subtitle: Text(
          [p.section, p.locationDescription, p.status]
              .where((s) => s != null)
              .join(' · '),
        ),
      ),
    );
  }
}

class _CemeteryRequestsTab extends ConsumerWidget {
  final String churchId;
  final bool isAdmin;
  final VoidCallback onNew;

  const _CemeteryRequestsTab({
    required this.churchId,
    required this.isAdmin,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedList<CemeteryServiceRequest>(
      future: ref.read(apiServiceProvider).listCemeteryRequests(churchId, limit: 50),
      itemBuilder: (r) => ListTile(
        title: Text(r.fullName),
        subtitle: Text('${r.type} · ${r.status}'),
        trailing: r.requestedDate != null ? Text(_shortDate(r.requestedDate!)) : null,
      ),
      floatingAction: FloatingActionButton(
        mini: true,
        onPressed: onNew,
        child: const Icon(Icons.add),
      ),
    );
  }
}

String _shortDate(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _PaginatedList<T> extends StatelessWidget {
  final Future<PaginatedResponse<T>> future;
  final Widget Function(T) itemBuilder;
  final Widget? floatingAction;

  const _PaginatedList({
    required this.future,
    required this.itemBuilder,
    this.floatingAction,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PaginatedResponse<T>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final items = snapshot.data?.data ?? [];
        if (items.isEmpty) {
          return const Center(child: Text('Nothing here yet.'));
        }
        return Stack(
          children: [
            ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => itemBuilder(items[i]),
            ),
            if (floatingAction != null)
              Positioned(
                right: 16,
                bottom: 16,
                child: floatingAction!,
              ),
          ],
        );
      },
    );
  }
}
