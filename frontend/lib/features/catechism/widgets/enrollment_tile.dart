import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/catechism_models.dart';
import 'status_chip.dart';

class EnrollmentTile extends StatelessWidget {
  final CatechismEnrollment enrollment;
  final VoidCallback? onWithdraw;

  const EnrollmentTile({super.key, required this.enrollment, this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(enrollment.studentName),
      subtitle: Text(
        '${enrollment.className ?? enrollment.classId}\n'
        'DOB: ${DateFormat.yMMMd().format(enrollment.dateOfBirth)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CatechismStatusChip(status: enrollment.status),
          if (onWithdraw != null) TextButton(onPressed: onWithdraw, child: const Text('Withdraw')),
        ],
      ),
    );
  }
}