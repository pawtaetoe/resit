import 'package:flutter/material.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';

/// Every booking length in one row of equal segments, so all are visible at
/// a glance.
class DurationPicker extends StatelessWidget {
  final int selected;

  /// The lengths that can be picked now; the rest show disabled.
  final List<int> available;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const DurationPicker({
    super.key,
    required this.selected,
    required this.available,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        segments: [
          for (final d in bookingLengths)
            ButtonSegment(
              value: d,
              enabled: enabled && available.contains(d),
              label: Text(durationLabel(d).replaceAll(' min', 'm').replaceAll(' h', 'h'),
                  semanticsLabel: durationLabel(d)),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
