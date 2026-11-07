import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';

const _kPurple = Color(0xFF702078);
const _kPurpleDark = Color(0xFF55204F);
const _kTint = Color(0xFFF6EEF7);

/// Full-screen hall detail + booking page. Opened when a hall card is tapped.
/// Shows the hall's image and info, start/end date-time pickers and a
/// "Book Hall" button. The button is only shown when [canBook] is true.
class HallDetailScreen extends ConsumerStatefulWidget {
  final Hall hall;
  final bool canBook;

  const HallDetailScreen({
    super.key,
    required this.hall,
    this.canBook = true,
  });

  @override
  ConsumerState<HallDetailScreen> createState() => _HallDetailScreenState();
}

class _HallDetailScreenState extends ConsumerState<HallDetailScreen> {
  late DateTime _start;
  late DateTime _end;
  final _purpose = TextEditingController();
  final _notes = TextEditingController();
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    // Default to the next whole hour, two-hour slot.
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour + 1);
    _end = _start.add(const Duration(hours: 2));
  }

  @override
  void dispose() {
    _purpose.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_start);
    if (picked == null) return;
    setState(() {
      _start = picked;
      // Keep end after start.
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_end);
    if (picked == null) return;
    setState(() => _end = picked);
  }

  Future<void> _book() async {
    if (!_end.isAfter(_start)) {
      _toast('End time must be after the start time.');
      return;
    }
    setState(() => _booking = true);
    try {
      await ref.read(apiServiceProvider).createBooking(widget.hall.churchId, {
        'hallId': widget.hall.id,
        // Backend requires RFC3339 with timezone; toUtc() appends 'Z'.
        'startDate': _start.toUtc().toIso8601String(),
        'endDate': _end.toUtc().toIso8601String(),
        'purpose': _purpose.text.trim().isEmpty ? null : _purpose.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      });
      if (!mounted) return;
      _toast('Booking requested');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _booking = false);
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hall;
    final fmt = DateFormat('EEE, d MMM yyyy  h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(h.name),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // Hero image.
          SizedBox(
            height: 200,
            width: double.infinity,
            child: h.images.isNotEmpty
                ? Image.network(
                    h.images.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (h.capacity != null)
                  _InfoRow(
                    icon: Icons.groups_outlined,
                    text: 'Capacity: ${h.capacity}',
                  ),
                if ((h.location ?? '').isNotEmpty)
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: h.location!,
                  ),
                if (h.price != null)
                  _InfoRow(
                    icon: Icons.sell_outlined,
                    text: 'Price: ${h.price}',
                  ),
                if ((h.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    h.description!,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
                const Divider(height: 32),
                const Text(
                  'Choose date & time',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _SlotTile(
                  label: 'Start',
                  value: fmt.format(_start),
                  onTap: _booking ? null : _pickStart,
                ),
                const SizedBox(height: 10),
                _SlotTile(
                  label: 'End',
                  value: fmt.format(_end),
                  onTap: _booking ? null : _pickEnd,
                ),
                if (widget.canBook) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _purpose,
                    decoration: const InputDecoration(
                      labelText: 'Purpose (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (widget.canBook)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _booking ? null : _book,
                      icon: _booking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.event_available),
                      label: Text(_booking ? 'Booking...' : 'Book Hall'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurpleDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Booking is not available for your account.',
                    style: TextStyle(color: Colors.black54),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFE8DCE9),
        child: const Center(
          child: Icon(Icons.meeting_room_outlined, color: _kPurple, size: 56),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _SlotTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: _kTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4D3E6)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: _kPurple),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.edit_calendar_outlined, color: _kPurple),
          ],
        ),
      ),
    );
  }
}
