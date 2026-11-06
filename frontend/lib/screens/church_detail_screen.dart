import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/auth_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/image_picker_field.dart';
import 'church_bookings_screen.dart';
import 'churches_screen.dart';
import 'event_chat_screen.dart';
import 'event_registrations_screen.dart';

const _kPurple = Color(0xFF702078);
const _kPurpleDark = Color(0xFF55204F);
const _kTint = Color(0xFFF6EEF7);
const _kTintBorder = Color(0xFFE4D3E6);

/// Church detail with role-aware management.
///
/// Layout: image gallery, name + "Book a Hall", pill tabs (About,
/// Announcements, Halls, Events, Bookings) and the tab content.
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
  static const int _announcementsTab = 1;
  static const int _bookingsTab = 4;

  late final TabController _tabController;

  /// The list endpoint returns a condensed church; the full record (gallery,
  /// description, clergy, contact) is fetched on open.
  late Church _church = widget.church;
  String? _loadError;

  /// Bumped after a booking is created so the Bookings tab reloads.
  int _bookingsVersion = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadChurch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadChurch() async {
    try {
      final full = await ref.read(apiServiceProvider).getChurch(widget.church.id);
      if (!mounted) return;
      setState(() {
        _church = full;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
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

  /// Opens the booking dialog (optionally for a specific hall) and, on
  /// success, jumps to the Bookings tab.
  Future<void> _book([String? hallId]) async {
    final created = await _showNewBookingDialog(
      context,
      ref,
      churchId: widget.church.id,
      preselectHallId: hallId,
      onError: _showError,
      onSuccess: _showSuccess,
    );
    if (created && mounted) {
      setState(() => _bookingsVersion++);
      _tabController.animateTo(_bookingsTab);
    }
  }

  /// Heart action: make this the signed-in member's church.
  Future<void> _setAsMyChurch() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    if (user.churchId == widget.church.id) {
      _showSuccess('This is already your church');
      return;
    }
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile({'churchId': widget.church.id});
      _showSuccess('Set as your church');
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _openChangeChurch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const ChurchesScreen(selectMode: true, popOnSelect: true),
      ),
    );
  }

  void _openManageBookings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChurchBookingsScreen(
          churchId: widget.church.id,
          churchName: widget.church.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final canManage = _canManage(user);
    final canManageContent = _canManageContent(user);
    final canBook = user?.role != 'super_admin';
    final isMyChurch = user?.churchId == widget.church.id;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: !widget.isHome,
        centerTitle: true,
        title: Text(
          _church.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (user?.role == 'user')
            IconButton(
              icon: Icon(isMyChurch ? Icons.favorite : Icons.favorite_border),
              color: _kPurple,
              tooltip: isMyChurch ? 'Your church' : 'Set as my church',
              onPressed: _setAsMyChurch,
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'change':
                  _openChangeChurch();
                case 'bookings':
                  _openManageBookings();
                case 'refresh':
                  _loadChurch();
              }
            },
            itemBuilder: (_) => [
              if (widget.isHome)
                const PopupMenuItem(
                    value: 'change', child: Text('Change church')),
              if (canManage)
                const PopupMenuItem(
                    value: 'bookings', child: Text('Manage bookings')),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerScrolled) => [
          SliverToBoxAdapter(child: _buildHeader(canBook)),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PillTabsDelegate(_tabController),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _AboutTab(
              church: _church,
              loadError: _loadError,
              canBook: canBook,
              onRefresh: _loadChurch,
              onViewAll: (i) => _tabController.animateTo(i),
              onBook: _book,
              onError: _showError,
              onSuccess: _showSuccess,
            ),
            _AnnouncementsTab(
              churchId: widget.church.id,
              canManage: canManageContent,
              onError: _showError,
              onSuccess: _showSuccess,
            ),
            _HallsTab(
              churchId: widget.church.id,
              canManage: canManage,
              canBook: canBook,
              onBook: _book,
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
            _BookingsTab(
              key: ValueKey(_bookingsVersion),
              churchId: widget.church.id,
              canBook: canBook,
              onError: _showError,
              onSuccess: _showSuccess,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool canBook) {
    final images = _church.images.isNotEmpty
        ? _church.images
        : [
            if (_church.logo != null && _church.logo!.isNotEmpty) _church.logo!,
          ];
    final address = _church.address ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Gallery(images: images),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _church.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 16, color: _kPurple),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (canBook) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _book(),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: const Text('Book a Hall'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
      title: 'Announcements',
      future: _future!,
      canManage: widget.canManage,
      onAdd: () => _form(),
      itemBuilder: (a) => _TintCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBDDED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.campaign_outlined, color: _kPurple),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 14, color: _kPurple),
                          const SizedBox(width: 6),
                          Text(_prettyDate(a.publishedAt ?? a.createdAt),
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.canManage)
                  _EditDeleteMenu(
                    onEdit: () => _form(existing: a),
                    onDelete: () => _delete(a),
                  ),
              ],
            ),
            if (a.image != null && a.image!.isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  a.image!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(a.content, style: const TextStyle(fontSize: 14, height: 1.35)),
          ],
        ),
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
  final bool canBook;
  final ValueChanged<String> onBook;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _HallsTab({
    required this.churchId,
    required this.canManage,
    required this.canBook,
    required this.onBook,
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
      title: 'Halls',
      future: _future!,
      canManage: widget.canManage,
      onAdd: () => _form(),
      itemBuilder: (h) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.white,
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _kTintBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                width: double.infinity,
                child: h.images.isNotEmpty
                    ? Image.network(
                        h.images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _hallPlaceholder(),
                      )
                    : _hallPlaceholder(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.name,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              if (h.capacity != null)
                                Row(
                                  children: [
                                    const Icon(Icons.groups_outlined,
                                        size: 16, color: _kPurple),
                                    const SizedBox(width: 6),
                                    Text('Capacity: ${h.capacity}',
                                        style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              if (h.price != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('Price: ${h.price}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54)),
                                ),
                            ],
                          ),
                        ),
                        if (widget.canBook)
                          TextButton(
                            onPressed: () => widget.onBook(h.id),
                            style: TextButton.styleFrom(
                              backgroundColor: _kTint,
                              foregroundColor: _kPurple,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Book',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        if (widget.canManage)
                          _EditDeleteMenu(
                            onEdit: () => _form(existing: h),
                            onDelete: () => _delete(h),
                          ),
                      ],
                    ),
                    if ((h.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(h.description!,
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hallPlaceholder() => Container(
        color: const Color(0xFFE8DCE9),
        child: const Center(
          child: Icon(Icons.meeting_room_outlined, color: _kPurple, size: 48),
        ),
      );
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
    super.key,
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
    final created = await _showNewBookingDialog(
      context,
      ref,
      churchId: widget.churchId,
      onError: widget.onError,
      onSuccess: widget.onSuccess,
    );
    if (created && mounted) _refresh();
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
      title: 'Events',
      future: _future!,
      canManage: widget.canManage,
      onAdd: () => _form(),
      itemBuilder: (e) {
        final start = e.startDate.toLocal();
        final time = e.endDate != null
            ? '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(e.endDate!.toLocal())}'
            : DateFormat('h:mm a').format(start);
        void openChat() => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EventChatScreen(event: e)),
            );
        return _TintCard(
          onTap: openChat,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBDDED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(DateFormat('MMM').format(start),
                        style: const TextStyle(
                            fontSize: 13,
                            color: _kPurple,
                            fontWeight: FontWeight.w600)),
                    Text(DateFormat('dd').format(start),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 15, color: _kPurple),
                        const SizedBox(width: 6),
                        Text(time, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    if ((e.location ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 15, color: _kPurple),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(e.location!,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Admins/staff post the events, so they don't register.
                        // Registration is only offered when the event requires it.
                        if (!widget.canManage &&
                            e.registrationRequired == true) ...[
                          TextButton.icon(
                            onPressed: () => widget.onRegister(e),
                            icon: const Icon(Icons.how_to_reg, size: 16),
                            label: const Text('Register'),
                            style: TextButton.styleFrom(
                              foregroundColor: _kPurple,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        TextButton.icon(
                          onPressed: openChat,
                          icon: const Icon(Icons.chat_bubble_outline, size: 16),
                          label: const Text('Chat'),
                          style: TextButton.styleFrom(
                            foregroundColor: _kPurple,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        if (widget.canManage) ...[
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EventRegistrationsScreen(event: e),
                              ),
                            ),
                            icon: const Icon(Icons.groups, size: 16),
                            label: const Text('Registered'),
                            style: TextButton.styleFrom(
                              foregroundColor: _kPurple,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.canManage)
                _EditDeleteMenu(
                  onEdit: () => _form(existing: e),
                  onDelete: () => _delete(e),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: Icon(Icons.chevron_right),
                ),
            ],
          ),
        );
      },
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

  /// Optional purple-barred section heading shown above the list.
  final String? title;

  const _ManagedList({
    required this.future,
    required this.itemBuilder,
    required this.canManage,
    this.onAdd,
    this.floatingAction,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final fab = floatingAction ??
        (canManage && onAdd != null
            ? FloatingActionButton(
                mini: true,
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) _SectionTitle(title!),
                  const Expanded(child: Center(child: Text('Nothing here yet.'))),
                ],
              )
            else
              ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                itemCount: items.length + (title != null ? 1 : 0),
                itemBuilder: (context, i) {
                  if (title != null) {
                    if (i == 0) return _SectionTitle(title!);
                    return itemBuilder(items[i - 1]);
                  }
                  return itemBuilder(items[i]);
                },
              ),
            if (fab != null)
              Positioned(right: 16, bottom: 16, child: fab),
          ],
        );
      },
    );
  }
}

/// Purple-barred section heading ("| Announcements").
class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: _kPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

/// Rounded lavender card used by the Announcements and Events lists.
class _TintCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _TintCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: _kTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _kTintBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ),
      );
}

String _prettyDate(DateTime d) => DateFormat('MMM d, y').format(d.toLocal());

// ---------------------------------------------------------------------------
// Booking dialog (shared by the header button, hall cards and Bookings tab).
// Returns true when a booking request was created.
// ---------------------------------------------------------------------------

Future<bool> _showNewBookingDialog(
  BuildContext context,
  WidgetRef ref, {
  required String churchId,
  String? preselectHallId,
  required void Function(String) onError,
  required void Function(String) onSuccess,
}) async {
  // Load halls for the picker first.
  List<Hall> halls;
  try {
    final res = await ref.read(apiServiceProvider).listHalls(churchId, limit: 100);
    halls = res.data;
  } catch (e) {
    onError(e.toString());
    return false;
  }
  if (!context.mounted) return false;
  if (halls.isEmpty) {
    onError('This church has no halls to book yet.');
    return false;
  }

  String? hallId = halls.any((h) => h.id == preselectHallId)
      ? preselectHallId
      : halls.first.id;
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
  if (confirmed != true || hallId == null) return false;

  try {
    await ref.read(apiServiceProvider).createBooking(churchId, {
      'hallId': hallId,
      // Backend requires RFC3339 (with timezone); toUtc() appends 'Z'.
      'startDate': start.toUtc().toIso8601String(),
      'endDate': end.toUtc().toIso8601String(),
      'purpose': purpose.text.isEmpty ? null : purpose.text,
      'notes': notes.text.isEmpty ? null : notes.text,
    });
    onSuccess('Booking requested');
    return true;
  } catch (e) {
    onError(e.toString());
    return false;
  }
}

// ---------------------------------------------------------------------------
// Header widgets: image gallery and pinned pill tab bar.
// ---------------------------------------------------------------------------

class _Gallery extends StatefulWidget {
  final List<String> images;

  const _Gallery({required this.images});

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final placeholder = Container(
      color: const Color(0xFFE8DCE9),
      child: const Center(
        child: Icon(Icons.church, size: 56, color: _kPurple),
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              placeholder
            else
              PageView.builder(
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Image.network(
                  images[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder,
                ),
              ),
            if (images.isNotEmpty)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_outlined,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '${_page + 1} / ${images.length}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillTabsDelegate extends SliverPersistentHeaderDelegate {
  final TabController controller;

  _PillTabsDelegate(this.controller);

  static const _tabs = <(IconData, String)>[
    (Icons.info_outline, 'About'),
    (Icons.campaign_outlined, 'Announcements'),
    (Icons.meeting_room_outlined, 'Halls'),
    (Icons.event_outlined, 'Events'),
    (Icons.event_seat_outlined, 'Bookings'),
  ];

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  bool shouldRebuild(covariant _PillTabsDelegate oldDelegate) =>
      oldDelegate.controller != controller;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: _kTintBorder,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.symmetric(vertical: 6),
        indicator: BoxDecoration(
          color: _kPurpleDark,
          borderRadius: BorderRadius.circular(22),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: _kPurpleDark,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: [
          for (final t in _tabs)
            Tab(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.$1, size: 18),
                    const SizedBox(width: 6),
                    Text(t.$2),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About tab: overview of the church (description, quick actions, clergy and
// previews of announcements, halls and upcoming events).
// ---------------------------------------------------------------------------

class _AboutTab extends ConsumerStatefulWidget {
  final Church church;
  final String? loadError;
  final bool canBook;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onViewAll;
  final ValueChanged<String?> onBook;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const _AboutTab({
    required this.church,
    required this.loadError,
    required this.canBook,
    required this.onRefresh,
    required this.onViewAll,
    required this.onBook,
    required this.onError,
    required this.onSuccess,
  });

  @override
  ConsumerState<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends ConsumerState<_AboutTab> {
  Future<PaginatedResponse<Announcement>>? _announcements;
  Future<PaginatedResponse<Hall>>? _halls;
  Future<PaginatedResponse<Event>>? _events;

  @override
  void initState() {
    super.initState();
    _reloadLists();
  }

  void _reloadLists() {
    final api = ref.read(apiServiceProvider);
    final id = widget.church.id;
    _announcements = api.listAnnouncements(id, limit: 3);
    _halls = api.listHalls(id, limit: 10);
    _events = api.listEvents(id, limit: 50);
  }

  Future<void> _refresh() async {
    setState(_reloadLists);
    await widget.onRefresh();
  }

  // ---- quick actions ------------------------------------------------------

  Future<void> _launch(Uri uri, String failMessage) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) widget.onError(failMessage);
    } catch (_) {
      widget.onError(failMessage);
    }
  }

  void _call() {
    final phone = widget.church.phone ?? '';
    if (phone.isEmpty) {
      widget.onError('No phone number available');
      return;
    }
    _launch(Uri(scheme: 'tel', path: phone), 'Could not start a call');
  }

  void _email() {
    final email = widget.church.email ?? '';
    if (email.isEmpty) {
      widget.onError('No email address available');
      return;
    }
    _launch(Uri(scheme: 'mailto', path: email), 'Could not open email app');
  }

  void _directions() {
    final address = widget.church.address ?? '';
    if (address.isEmpty) {
      widget.onError('No address available');
      return;
    }
    _launch(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '${widget.church.name}, $address',
      }),
      'Could not open maps',
    );
  }

  Future<void> _share() async {
    final c = widget.church;
    final text = [
      c.name,
      if ((c.address ?? '').isNotEmpty) c.address!,
      if ((c.phone ?? '').isNotEmpty) c.phone!,
      if ((c.email ?? '').isNotEmpty) c.email!,
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    widget.onSuccess('Church details copied to clipboard');
  }

  // ---- building blocks ----------------------------------------------------

  Widget _sectionHeader(String title, {VoidCallback? onViewAll}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: _kPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                child: const Text('View All'),
              ),
          ],
        ),
      );

  Widget _tintedCard({required Widget child, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: _kTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _kTintBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(12), child: child),
          ),
        ),
      );

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: _kTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _kTintBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(icon, color: _kPurple),
                    const SizedBox(height: 4),
                    Text(label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  /// Renders a future list as a section body with loading/error/empty states.
  Widget _futureBody<T>(
    Future<PaginatedResponse<T>>? future,
    String emptyText,
    Widget Function(List<T>) builder,
  ) {
    return FutureBuilder<PaginatedResponse<T>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError) {
          return Text('Error: ${snap.error}',
              style: const TextStyle(color: Colors.red));
        }
        final items = snap.data?.data ?? <T>[];
        if (items.isEmpty) {
          return Text(emptyText, style: const TextStyle(color: Colors.black54));
        }
        return builder(items);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final church = widget.church;
    final description = church.description ?? '';
    final address = church.address ?? '';

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _sectionHeader('About'),
          Text(
            description.isNotEmpty ? description : 'No description available.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (widget.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Could not load full details: ${widget.loadError}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (church.priest != null || church.associatePriest != null) ...[
            const SizedBox(height: 12),
            if (church.priest != null) _priestCard('Priest', church.priest!),
            if (church.associatePriest != null)
              _priestCard('Associate Priest', church.associatePriest!),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _actionButton(Icons.phone_outlined, 'Call', _call),
              _actionButton(Icons.email_outlined, 'Email', _email),
              _actionButton(Icons.location_on_outlined, 'Directions', _directions),
              _actionButton(Icons.share_outlined, 'Share', _share),
            ],
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 12),
            _tintedCard(
              onTap: _directions,
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: _kPurple),
                  const SizedBox(width: 10),
                  Expanded(child: Text(address)),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],

          // Latest announcements.
          _sectionHeader('Latest Announcements', onViewAll: () => widget.onViewAll(1)),
          _futureBody<Announcement>(
            _announcements,
            'No announcements yet.',
            (items) => Column(
              children: items.take(2).map((a) {
                final date = a.publishedAt ?? a.createdAt;
                return _tintedCard(
                  onTap: () => widget.onViewAll(1),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFFEBDDED),
                        child: Icon(Icons.campaign_outlined, color: _kPurple),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(a.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MMM d, y').format(date.toLocal()),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Halls.
          _sectionHeader('Halls', onViewAll: () => widget.onViewAll(2)),
          _futureBody<Hall>(
            _halls,
            'No halls yet.',
            (items) => SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _hallCard(items[i]),
              ),
            ),
          ),

          // Upcoming events.
          _sectionHeader('Upcoming Events', onViewAll: () => widget.onViewAll(3)),
          _futureBody<Event>(
            _events,
            'No events yet.',
            (all) {
              final now = DateTime.now();
              final upcoming = all
                  .where((e) => (e.endDate ?? e.startDate).isAfter(now))
                  .toList()
                ..sort((a, b) => a.startDate.compareTo(b.startDate));
              if (upcoming.isEmpty) {
                return const Text('No upcoming events.',
                    style: TextStyle(color: Colors.black54));
              }
              return Column(children: upcoming.take(3).map(_eventTile).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _hallCard(Hall h) {
    return SizedBox(
      width: 170,
      child: Material(
        color: Colors.white,
        elevation: 1.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _kTintBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onViewAll(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 100,
                width: double.infinity,
                child: h.images.isNotEmpty
                    ? Image.network(
                        h.images.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _hallPlaceholder(),
                      )
                    : _hallPlaceholder(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: Text(h.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        h.capacity != null ? 'Capacity: ${h.capacity}' : '',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                    ),
                    if (widget.canBook)
                      TextButton(
                        onPressed: () => widget.onBook(h.id),
                        style: TextButton.styleFrom(
                          backgroundColor: _kTint,
                          foregroundColor: _kPurple,
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Book'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hallPlaceholder() => Container(
        color: const Color(0xFFE8DCE9),
        child: const Center(
          child: Icon(Icons.meeting_room_outlined, color: _kPurple, size: 36),
        ),
      );

  Widget _eventTile(Event e) {
    final start = e.startDate.toLocal();
    final time = e.endDate != null
        ? '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(e.endDate!.toLocal())}'
        : DateFormat('h:mm a').format(start);
    return _tintedCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EventChatScreen(event: e)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kTintBorder),
            ),
            child: Column(
              children: [
                Text(DateFormat('MMM').format(start),
                    style: const TextStyle(
                        fontSize: 12,
                        color: _kPurple,
                        fontWeight: FontWeight.w600)),
                Text(DateFormat('d').format(start),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: _kPurple),
                    const SizedBox(width: 4),
                    Text(time, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _priestCard(String role, PriestDetails p) {
    final contact = [
      if ((p.phone ?? '').isNotEmpty) p.phone!,
      if ((p.email ?? '').isNotEmpty) p.email!,
    ].join('  •  ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
