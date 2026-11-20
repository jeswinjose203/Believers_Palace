import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/catechism_models.dart';

class SessionTile extends StatelessWidget {
  final CatechismSession session;
  final VoidCallback? onEdit;

  const SessionTile({super.key, required this.session, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();
    return ListTile(
      title: Text(session.title),
      subtitle: Text(
        '${df.format(session.sessionDate)} · ${session.startTime} – ${session.endTime}'
        '${session.topic != null ? '\n${session.topic}' : ''}',
      ),
      trailing: onEdit != null ? IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit) : null,
    );
  }
}