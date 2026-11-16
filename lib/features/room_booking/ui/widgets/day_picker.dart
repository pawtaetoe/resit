import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';

/// A row of chips for the days a room can be booked, today first.
class DayPicker extends StatelessWidget {
  final DateTime selected;

  /// Null while the days can't be changed.
  final ValueChanged<DateTime>? onSelected;

  const DayPicker({super.key, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 0; i <= bookingDaysAhead; i++) DateTime(today.year, today.month, today.day + i),
    ].where((d) => earliestStart(d, now) != null).toList();
    final onSelected = this.onSelected;

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = days[i];
          final diff = d.difference(today).inDays;
          final top = diff == 0
              ? 'Today'
              : diff == 1
                  ? 'Tmrw'
                  : DateFormat('EEE').format(d);
          final isSelected = d == selected;
          final scheme = Theme.of(context).colorScheme;
          return ChoiceChip(
            showCheckmark: false,
            selected: isSelected,
            onSelected: onSelected == null ? null : (_) => onSelected(d),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(top,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: isSelected ? null : scheme.onSurfaceVariant)),
                Text(DateFormat('d MMM').format(d), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          );
        },
      ),
    );
  }
}
