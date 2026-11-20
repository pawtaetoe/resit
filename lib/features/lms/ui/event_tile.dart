import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// "Today · Thu 20 Nov", "Tomorrow · Fri 21 Nov", "Mon 24 Nov".
String agendaDayLabel(DateTime day, DateTime now) {
  final date = DateFormat(day.year == now.year ? 'EEE d MMM' : 'EEE d MMM yyyy').format(day);
  if (DateUtils.isSameDay(day, now)) return 'Today · $date';
  if (DateUtils.isSameDay(day, DateTime(now.year, now.month, now.day + 1))) return 'Tomorrow · $date';
  return date;
}

/// When [e] happens, as listed under [day]: "All day", "23:59",
/// "10:00 – 12:00", "Until Fri 21 Nov, 18:00", ...
String eventTimeLabel(LmsEvent e, DateTime day) {
  final time = DateFormat('HH:mm');
  final date = DateFormat('EEE d MMM');
  if (e.allDay) {
    final lastDay = e.end?.subtract(const Duration(days: 1));
    return lastDay != null && lastDay.isAfter(e.start) ? 'All day · until ${date.format(lastDay)}' : 'All day';
  }
  final end = e.end;
  if (e.isInstant || end == null) return time.format(e.start);
  if (DateUtils.isSameDay(e.start, end)) return '${time.format(e.start)} – ${time.format(end)}';
  if (!DateUtils.isSameDay(e.start, day)) return 'Until ${date.format(end)}, ${time.format(end)}';
  return '${time.format(e.start)} – ${date.format(end)}, ${time.format(end)}';
}

IconData _icon(LmsEventKind kind) => switch (kind) {
      LmsEventKind.assignment => Icons.assignment_outlined,
      LmsEventKind.quiz => Icons.quiz_outlined,
      LmsEventKind.content => Icons.description_outlined,
      LmsEventKind.discussion => Icons.forum_outlined,
      LmsEventKind.checklist => Icons.checklist,
      LmsEventKind.grade => Icons.grade_outlined,
      LmsEventKind.survey => Icons.poll_outlined,
      LmsEventKind.event => Icons.event_outlined,
    };

/// One calendar event: what, which course, when, where. Opens its item (or
/// its calendar page) on xSiTe.
class EventTile extends StatelessWidget {
  final LmsEvent event;
  final DateTime day;
  final bool showCourse;
  const EventTile({super.key, required this.event, required this.day, this.showCourse = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final e = event;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => openInBrowser(context, e.url),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Icon(_icon(e.kind)),
          ),
          title: Text(e.title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [if (showCourse && e.courseCode.isNotEmpty) e.courseCode, eventTimeLabel(e, day)].join(' · '),
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
              ),
              if (e.location.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(e.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    ),
                  ],
                ),
            ],
          ),
          trailing: Icon(Icons.open_in_new, size: 18, semanticLabel: 'Opens in xSiTe', color: muted),
        ),
      ),
    );
  }
}
