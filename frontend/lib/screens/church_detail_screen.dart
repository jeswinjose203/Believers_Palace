import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';
import 'church_bookings_screen.dart';
import 'churches_screen.dart';
import 'event_chat_screen.dart';

/// Church detail with role-aware management.
///
/// - super_admin / church_admin (own church): full control of halls, bookings,
///   and booking status.
/// - super_admin / church staff (priest, associate_priest, church_admin, own
///   church): manage pastoral content (announcements, events).
/// - everyone: browse, book halls, register for events.
class ChurchDetailScreen extends ConsumerStatefulWidget {
  final Church church;

  /// True when shown as the user's home page: no back button, and a
  /// "Change church" action.
  final bool isHome;

  const ChurchDetailScreen({
    super.key,
    required this.church,
    this.isHome = false,
  });

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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Full administrative control (halls, booking status).
  bool _canManage(User? user) {
    if (user == null) return false;
    if (user.role == 'super_admin') return true;
    return user.role == 'church_admin' && user.churchId == widget.church.id;
  }

  /// Pastoral content management (announcements, events).
  bool _canManageContent(User? user) {
    if (user == null) return false;
    if (user.role == 'super_admin') return true;
    const staff = {'priest', 'associate_priest', 'church_admin'};
    return staff.contains(user.role) && user.churchId == widget.church.id;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final canManage = _canManage(user);
    final canManageContent = _canManageContent(user);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.church.name),
        automaticallyImplyLeading: !widget.isHome,
        actions: [
          if (widget.isHome)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Change church',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChurchesScreen(
                      selectMode: true, popOnSelect: true),
                ),
              ),
            ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.event_available),
              tooltip: 'Manage bookings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChurchBookingsScreen(
                    churchId: widget.church.id,
                    churchName: widget.church.name,
                  ),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'About'),
            Tab(text: 'Announcements'),
            Tab(text: 'Halls'),
            Tab(text: 'Bookings'),
            Tab(text: 'Events'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AboutTab(churchId: widget.church.id, initial: widget.church),
          _AnnouncementsTab(
            churchId: widget.church.id,
            canManage: canManageContent,
            onError: _showError,
            onSuccess: _showSuccess,
          ),
          _HallsTab(
            churchId: widget.church.id,
            canManage: canManage,
            onError: _showError,
            onSuccess: _showSuccess,
          ),
          _BookingsTab(
            churchId: widget.church.id,
            canBook: user?.role != 'super_admin',
            onError: _showError,
            onSuccess: _showSuccess,
          ),
          _EventsTab(
            churchId: widget.church.id,
            canManage: canManageContent,
            onRegister: _showRegisterDialog,
            onError: _showError,
            onSuccess: _showSuccess,
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
}

// ---------------------------------------------------------------------------
// Shared date/time field.
// ---------------------------------------------------------------------------

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
      contentPadding: EdgeInsets.zero,
      title: Text(widget.label),
      subtitle: Text(_value.toLocal().toString()),
      trailing: const Icon(Icons.calendar_today),
      onTap: _pick,
    );
  }
}

// ---------------------------------------------------------------------------
// Announcements.
// ---------------------------------------------------------------------------

class _AnnouncementsTab extends ConsumerStatefulWidget {
  final String churchId;
  final bool canManage;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _AnnouncementsTab({
    required this.churchId,
    required this.canManage,
    required this.onError,
    required this.onSuccess,
  });

  @override
  ConsumerState<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends ConsumerState<_AnnouncementsTab> {
  Future<PaginatedResponse<Announcement>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future =
        ref.read(apiServiceProvider).listAnnouncements(widget.churchId, limit: 50);
  }

  void _refresh() => setState(_reload);

  Future<void> _form({Announcement? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final content = TextEditingController(text: existing?.content ?? '');
    String? image = existing?.image;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'New Announcement' : 'Edit Announcement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              TextField(
                controller: content,
                decoration: const InputDecoration(labelText: 'Content *'),
                maxLines: 4,
              ),
              ImagePickerField(
                label: 'Image',
                initialUrl: existing?.image,
                onChanged: (url) => image = url,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final body = {
      'title': title.text,
      'content': content.text,
      'image': (image == null || image!.isEmpty) ? null : image,
    };
    try {
      final api = ref.read(apiServiceProvider);
      if (existing == null) {
        await api.createAnnouncement(widget.churchId, body);
      } else {
        await api.updateAnnouncement(existing.id, body);
      }
      widget.onSuccess('Saved');
      _refresh();
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  Future<void> _delete(Announcement a) async {
    if (!await _confirmDelete(context, a.title)) return;
    try {
      await ref.read(apiServiceProvider).deleteAnnouncement(a.id);
      widget.onSuccess('Deleted');
      _refresh();
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ManagedList<Announcement>(
      future: _future!,
      canManage: widget.canManage,
      onAdd: () => _form(),
      itemBuilder: (a) => ListTile(
        leading: (a.image != null && a.image!.isNotEmpty)
            ? CircleAvatar(backgroundImage: NetworkImage(a.image!))
            : const CircleAvatar(child: Icon(Icons.campaign)),
        title: Text(a.title),
        subtitle: Text(a.content, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: widget.canManage
            ? _EditDeleteMenu(
                onEdit: () => _form(existing: a),
                onDelete: () => _delete(a),
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Halls.
// ---------------------------------------------------------------------------

class _HallsTab extends ConsumerStatefulWidget {
  final String churchId;
  final bool canManage;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _HallsTab({
    required this.churchId,
    required this.canManage,
    required this.onError,
    required this.onSuccess,
  });

  @override
  ConsumerState<_HallsTab> createState() => _HallsTabState();
}

class _HallsTabState extends ConsumerState<_HallsTab> {
  Future<PaginatedResponse<Hall>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiServiceProvider).listHalls(widget.churchId, limit: 50);
  }

  void _refresh() => setState(_reload);

  Future<void> _form({Hall? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(text: existing?.description ?? '');
    final capacity =
        TextEditingController(text: existing?.capacity?.toString() ?? '');
    final location = TextEditingController(text: existing?.location ?? '');
    final price = TextEditingController(text: existing?.price?.toString() ?? '');
    final images = List<String>.from(existing?.images ?? const []);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'New Hall' : 'Edit Hall'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name *'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: capacity,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                TextField(
                  controller: price,
                  decoration: const InputDecoration(labelText: 'Price'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                ...images.asMap().entries.map(
                      (e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                            backgroundImage: NetworkImage(e.value)),
                        title: Text('Image ${e.key + 1}',
                            overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => images.removeAt(e.key)),
                        ),
                      ),
                    ),
                ImagePickerField(
                  label: 'Add image',
                  onChanged: (url) {
                    if (url != null && url.isNotEmpty) {
                      setState(() => images.add(url));
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;

    final body = {
      'name': name.text,
      'description': description.text.isEmpty ? null : description.text,
      'capacity': int.tryParse(capacity.text),
      'location': location.text.isEmpty ? null : location.text,
      'price': double.tryParse(price.text),
      'images': images,
    };
    try {
      final api = ref.read(apiServiceProvider);
      if (existing == null) {
        await api.createHall(widget.churchId, body);
      } else {
        await api.updateHall(existing.id, body);
      }
      widget.onSuccess('Saved');
      _refresh();
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  Future<void> _delete(Hall h) async {
    if (!await _confirmDelete(context, h.name)) return;
    try {
      await ref.read(apiServiceProvider).deleteHall(h.id);
      widget.onSuccess('Deleted');
      _refresh();
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ManagedList<Hall>(
      future: _future!,
      canManage: widget.canManage,
      onAdd: () => _form(),
      itemBuilder: (h) => ListTile(
        leading: (h.images.isNotEmpty)
            ? CircleAvatar(backgroundImage: NetworkImage(h.images.first))
            : const CircleAvatar(child: Icon(Icons.meeting_room)),
        title: Text(h.name),
        subtitle: Text(
          [
            if (h.location != null) h.location,
            if (h.capacity != null) 'Capacity: ${h.capacity}',
            if (h.price != null) 'Price: ${h.price}',
          ].where((s) => s != null).join(' · '),
        ),
        trailing: widget.canManage
            ? _EditDeleteMenu(
                onEdit: () => _form(existing: h),
                onDelete: () => _delete(h),
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookings (dedicated section: pick a hall, choose a time range).
// ---------------------------------------------------------------------------

class _BookingsTab extends ConsumerStatefulWidget {
  final String churchId;
  final bool canBook;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _BookingsTab({
    required this.churchId,
    required this.canBook,
    required this.onError,
    required this.onSuccess,
  });

  @override
  ConsumerState<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<_BookingsTab> {
  Future<PaginatedResponse<Booking>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    // Church bookings endpoint returns the caller's own bookings for regular
    // users and all bookings for admins; either way it scopes to this church.
    _future = ref
        .read(apiServiceProvider)
        .listChurchBookings(widget.churchId, limit: 50);
  }

  void _refresh() => setState(_reload);

  Future<void> _newBooking() async {
    // Load halls for the picker first.
    List<Hall> halls;
    try {
      final res =
          await ref.read(apiServiceProvider).listHalls(widget.churchId, limit: 100);
      halls = res.data;
    } catch (e) {
      widget.onError(e.toString());
      return;
    }
    if (!mounted) return;
    if (halls.isEmpty) {
      widget.onError('This church has no halls to book yet.');
      return;
    }

    String? hallId = halls.first.id;
    final purpose = TextEditingController();
    final notes = TextEditingController();
    DateTime start = DateTime.now();
    DateTime end = start.add(const Duration(hours: 2));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New Booking'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: hallId,
                  decoration: const InputDecoration(labelText: 'Hall *'),
                  items: halls
                      .map((h) =>
                          DropdownMenuItem(value: h.id, child: Text(h.name)))
                      .toList(),
                  onChanged: (v) => setState(() => hallId = v),
                ),
                _DateTimeField(
                  label: 'Start',
                  initial: start,
                  onPicked: (d) => start = d ?? start,
                ),
                _DateTimeField(
                  label: 'End',
                  initial: end,
                  onPicked: (d) => end = d ?? end,
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Request booking'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || hallId == null) return;

    try {
      await ref.read(apiServiceProvider).createBooking(widget.churchId, {
        'hallId': hallId,
        // Backend requires RFC3339 (with timezone); toUtc() appends 'Z'.
        'startDate': start.toUtc().toIso8601String(),
        'endDate': end.toUtc().toIso8601String(),
        'purpose': purpose.text.isEmpty ? null : purpose.text,
        'notes': notes.text.isEmpty ? null : notes.text,
      });
      widget.onSuccess('Booking requested');
      _refresh();
    } catch (e) {
      widget.onError(e.toString());
    }
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

  @override
  Widget build(BuildContext context) {
    return _ManagedList<Booking>(
      future: _future!,
      canManage: false,
      onAdd: null,
      floatingAction: widget.canBook
          ? FloatingActionButton.extended(
              onPressed: _newBooking,
              icon: const Icon(Icons.add),
              label: const Text('Book a hall'),
            )
          : null,
      itemBuilder: (b) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.event_seat)),
        title: Text('${_shortDate(b.startDate)} → ${_shortDate(b.endDate)}'),
        subtitle: Text('Purpose: ${b.purpose ?? "-"}'),
        trailing: Chip(
          label: Text(b.status),
          backgroundColor: _statusColor(b.status),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Events.
// ---------------------------------------------------------------------------

class _EventsTab extends ConsumerStatefulWidget {
  final String churchId;
  final bool canManage;
  final ValueChanged<Event> onRegister;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _EventsTab({
    required this.churchId,
    required this.canManage,
    required this.onRegister,
    required this.onError,
    required this.onSuccess,
  });

  @override
  ConsumerState<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<_EventsTab> {
  Future<PaginatedResponse<Event>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(apiServiceProvider).listEvents(widget.churchId, limit: 50);
  }

  void _refresh() => setState(_reload);

  Future<void> _form({Event? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final description = TextEditingController(text: existing?.description ?? '');
    final location = TextEditingController(text: existing?.location ?? '');
    DateTime startDate = existing?.startDate ?? DateTime.now();
    DateTime? endDate = existing?.endDate;
    bool registrationRequired = existing?.registrationRequired ?? false;
    String? image = existing?.image;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'New Event' : 'Edit Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                _DateTimeField(
                  label: 'Start date *',
                  initial: startDate,
                  onPicked: (d) => startDate = d ?? startDate,
                ),
                _DateTimeField(
                  label: 'End date (optional)',
                  initial: endDate ?? startDate.add(const Duration(hours: 2)),
                  onPicked: (d) => endDate = d,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Registration required'),
                  value: registrationRequired,
                  onChanged: (v) => setState(() => registrationRequired = v),
                ),
                ImagePickerField(
                  label: 'Image',
                  initialUrl: existing?.image,
                  onChanged: (url) => image = url,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;

    final body = {
      'title': title.text,
      'description': description.text.isEmpty ? null : description.text,
      'location': location.text.isEmpty ? null : location.text,
      // Capacity is no longer editable in the UI; keep any existing value.
      'capacity': existing?.capacity,
      // RFC3339 with timezone ('Z') is required by the backend.
      'startDate': startDate.toUtc().toIso8601String(),
      'endDate': endDate?.toUtc().toIso8601String(),
      'registrationRequired': registrationRequired,
      'image': (image == null || image!.isEmpty) ? null : image,
    };
    try {
      final api = ref.read(apiServiceProvider);
      if (existing == null) {
        await api.createEvent(widget.churchId, body);
      } else {
        await api.updateEvent(existing.id, body);
      }
      widget.onSuccess('Saved');
      _refresh();
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  Future<void> _delete(Event e) async {
    if (!await _confirmDelete(context, e.title)) return;
    try {
      await ref.read(apiServiceProvider).deleteEvent(e.id);
      widget.onSuccess('Deleted');
      _refresh();
    } catch (err) {
      widget.onError(err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ManagedList<Event>(
      future: _future!,
      canManage: widget.canManage,
      onAdd: () => _form(),
      itemBuilder: (e) => ListTile(
        leading: (e.image != null && e.image!.isNotEmpty)
            ? CircleAvatar(backgroundImage: NetworkImage(e.image!))
            : const CircleAvatar(child: Icon(Icons.event)),
        title: Text(e.title),
        subtitle: Text(
          '${_shortDate(e.startDate)}${e.location != null ? ' · ${e.location}' : ''}',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventChatScreen(event: e)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'Chat',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventChatScreen(event: e)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.how_to_reg),
              tooltip: 'Register',
              onPressed: () => widget.onRegister(e),
            ),
            if (widget.canManage)
              _EditDeleteMenu(
                onEdit: () => _form(existing: e),
                onDelete: () => _delete(e),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared list + helpers.
// ---------------------------------------------------------------------------

Future<bool> _confirmDelete(BuildContext context, String label) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "$label"?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _EditDeleteMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EditDeleteMenu({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

String _shortDate(DateTime d) {
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A paginated list with an optional "add" FAB (shown when [canManage]) and an
/// optional custom [floatingAction].
class _ManagedList<T> extends StatelessWidget {
  final Future<PaginatedResponse<T>> future;
  final Widget Function(T) itemBuilder;
  final bool canManage;
  final VoidCallback? onAdd;
  final Widget? floatingAction;

  const _ManagedList({
    required this.future,
    required this.itemBuilder,
    required this.canManage,
    this.onAdd,
    this.floatingAction,
  });

  @override
  Widget build(BuildContext context) {
    final fab = floatingAction ??
        (canManage && onAdd != null
            ? FloatingActionButton(
                mini: true,
                onPressed: onAdd,
                child: const Icon(Icons.add),
              )
            : null);

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
        return Stack(
          children: [
            if (items.isEmpty)
              const Center(child: Text('Nothing here yet.'))
            else
              ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => itemBuilder(items[i]),
              ),
            if (fab != null)
              Positioned(right: 16, bottom: 16, child: fab),
          ],
        );
      },
    );
  }
}


/// First tab of the church detail screen: gallery, description, contact info
/// and the priests associated with the church. The list endpoint only returns
/// a condensed church, so the full record is fetched here.
class _AboutTab extends ConsumerStatefulWidget {
  final String churchId;
  final Church initial;

  const _AboutTab({required this.churchId, required this.initial});

  @override
  ConsumerState<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends ConsumerState<_AboutTab> {
  late Church church = widget.initial;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final full = await ref.read(apiServiceProvider).getChurch(widget.churchId);
      if (!mounted) return;
      setState(() {
        church = full;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = church.images.isNotEmpty
        ? church.images
        : [if (church.logo != null && church.logo!.isNotEmpty) church.logo!];
    final hasDescription = (church.description ?? '').isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load full details: $_error',
                style: const TextStyle(color: Colors.red)),
          ),
        if (images.isNotEmpty)
          SizedBox(
            height: 220,
            child: PageView.builder(
              itemCount: images.length,
              itemBuilder: (_, i) => Image.network(
                images[i],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(church.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                hasDescription
                    ? church.description!
                    : 'No description available.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if ((church.address ?? '').isNotEmpty)
                _infoRow(Icons.location_on_outlined, church.address!),
              if ((church.phone ?? '').isNotEmpty)
                _infoRow(Icons.phone_outlined, church.phone!),
              if ((church.email ?? '').isNotEmpty)
                _infoRow(Icons.email_outlined, church.email!),
              if (church.priest != null || church.associatePriest != null) ...[
                const SizedBox(height: 16),
                Text('Clergy', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (church.priest != null)
                  _priestCard('Priest', church.priest!),
                if (church.associatePriest != null)
                  _priestCard('Associate Priest', church.associatePriest!),
              ],
            ],
          ),
        ),
      ],
    ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );

  Widget _priestCard(String role, PriestDetails p) {
    final contact = [
      if ((p.phone ?? '').isNotEmpty) p.phone!,
      if ((p.email ?? '').isNotEmpty) p.email!,
    ].join('  •  ');
    return Card(
      child: ListTile(
        leading: (p.profilePic ?? '').isNotEmpty
            ? CircleAvatar(backgroundImage: NetworkImage(p.profilePic!))
            : const CircleAvatar(child: Icon(Icons.person)),
        title: Text(p.name ?? ''),
        subtitle: Text(contact.isEmpty ? role : '$role\n$contact'),
        isThreeLine: contact.isNotEmpty,
      ),
    );
  }
}
