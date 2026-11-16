import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/timetable/domain/class_session.dart';

/// Shows a class's details in a bottom sheet: the module, its type and
/// section, the date, time and place, and whether it clashes.
void showClassDetails(BuildContext context, ClassSession s) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Sized to its content (not capped at half the screen), so larger text
    // sizes aren't cut off; it scrolls if it's taller than the screen.
    isScrollControlled: true,
    // Keeps the details clear of the system navigation bar.
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.courseCode, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _DetailRow(Icons.class_outlined, '${s.component} · ${s.section}'),
            _DetailRow(Icons.calendar_today_outlined, DateFormat('EEEE, d MMM yyyy').format(s.date)),
            _DetailRow(Icons.schedule, s.timeLabel),
            if (s.location.isNotEmpty) _DetailRow(Icons.place_outlined, s.location),
            if (s.coinciding) ...[
              const SizedBox(height: 8),
              const StatusPill(
                label: 'Clashes with another class',
                tone: Tone.warning,
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One line of the details: an icon and its text.
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );
}
