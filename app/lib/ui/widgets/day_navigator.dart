import 'package:flutter/material.dart';

import '../../core/dates.dart';

/// "< Hoy, sábado 3 de octubre >" with a date picker; never goes past today.
class DayNavigator extends StatelessWidget {
  const DayNavigator({super.key, required this.day, required this.onChanged});

  final DateTime day;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final isToday = day == today;
    return Row(
      children: [
        IconButton(
          onPressed: () => onChanged(day.subtract(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Día anterior',
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime(2024),
                lastDate: today,
              );
              if (picked != null) onChanged(dateOnly(picked));
            },
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(isToday ? 'Hoy, ${longDayLabel(day)}' : longDayLabel(day)),
          ),
        ),
        IconButton(
          onPressed: isToday ? null : () => onChanged(day.add(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Día siguiente',
        ),
      ],
    );
  }
}
