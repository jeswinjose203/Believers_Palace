import 'package:flutter/material.dart';

class CatechismStatusChip extends StatelessWidget {
  final String status;

  const CatechismStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = _style(status);
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  (Color, String) _style(String s) {
    switch (s) {
      case 'pending':
        return (Colors.amber.shade700, 'Pending');
      case 'approved':
        return (Colors.green.shade700, 'Approved');
      case 'rejected':
        return (Colors.red.shade700, 'Rejected');
      case 'withdrawn':
        return (Colors.grey.shade600, 'Withdrawn');
      case 'completed':
        return (Colors.blue.shade700, 'Completed');
      case 'open':
        return (Colors.green.shade600, 'Open');
      case 'closed':
        return (Colors.orange.shade800, 'Closed');
      case 'draft':
        return (Colors.grey.shade500, 'Draft');
      default:
        return (Colors.blueGrey, s);
    }
  }
}