import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/catechism_models.dart';
import 'status_chip.dart';

class CatechismClassCard extends StatelessWidget {
  final CatechismClass item;
  final VoidCallback? onTap;

  const CatechismClassCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.image != null && item.image!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item.image!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  ),
                )
              else
                _placeholder(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(levelLabel(item.level), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('${df.format(item.startDate)} – ${df.format(item.endDate)}'),
                    Text('${item.availableSeats} seats left · ${item.enrolledCount}/${item.capacity} enrolled'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        CatechismStatusChip(status: item.status),
                        if (item.enrolled)
                          const Chip(
                            label: Text('Enrolled', style: TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
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

  Widget _placeholder() => Container(
        width: 72,
        height: 72,
        color: Colors.indigo.shade50,
        child: const Icon(Icons.school_outlined),
      );
}