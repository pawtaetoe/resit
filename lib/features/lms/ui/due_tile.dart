import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// "Today, 23:59", "Tomorrow, 14:00", "Fri 21 Nov, 23:59"; "Was due …" once past.
String dueLabel(DateTime due, DateTime now) {
  final day = DateUtils.isSameDay(due, now)
      ? 'Today'
      : DateUtils.isSameDay(due, now.add(const Duration(days: 1)))
          ? 'Tomorrow'
          : DateFormat(due.year == now.year ? 'EEE d MMM' : 'EEE d MMM yyyy').format(due);
  final at = '$day, ${DateFormat('HH:mm').format(due)}';
  return due.isBefore(now) ? 'Was due $at' : 'Due $at';
}

/// How urgent a deadline is: past (danger), within a day (warning), later.
Tone dueTone(DateTime due, DateTime now) => due.isBefore(now)
    ? Tone.danger
    : due.difference(now) < const Duration(days: 1)
        ? Tone.warning
        : Tone.neutral;

/// One deadline: what, which course, when (coloured by urgency). Opens on
/// xSiTe.
class DueTile extends StatelessWidget {
  final DueItem item;
  final DateTime now;
  final bool showCourse;
  const DueTile({super.key, required this.item, required this.now, this.showCourse = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = dueTone(item.due, now);
    final (bg, fg) = tone.colors(theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => openInBrowser(context, item.url),
          leading: CircleAvatar(
            backgroundColor: bg,
            foregroundColor: fg,
            child: Icon(item.isQuiz ? Icons.quiz_outlined : Icons.assignment_outlined),
          ),
          title: Text(showCourse ? '${item.courseCode} · ${item.title}' : item.title,
              style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(dueLabel(item.due, now),
              style: tone == Tone.neutral ? null : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.open_in_new, size: 18),
        ),
      ),
    );
  }
}
