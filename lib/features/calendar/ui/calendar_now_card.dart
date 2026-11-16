import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';

/// Where today is: "Week 10 · Trimester 1", progress through the trimester,
/// and the next change (recess, finals, break). Between trimesters, when the
/// next one starts.
class CalendarNowCard extends StatelessWidget {
  final AcademicCalendar calendar;
  final CalendarPosition? position;
  final DateTime today;

  const CalendarNowCard({super.key, required this.calendar, required this.position, required this.today});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onPrimaryContainer;
    final d = DateFormat('EEE d MMM');
    final p = position;

    final Widget content;
    if (p == null) {
      final next = calendar.nextTermAfter(today);
      content = Text(
        next == null
            ? "Today isn't covered by the published calendar."
            : 'Between trimesters. ${next.$2.name} (${next.$1.label}) starts ${d.format(next.$2.start)}.',
        style: theme.textTheme.titleMedium?.copyWith(color: fg),
      );
    } else {
      final termWeeks = p.term.termWeeks;
      final done = termWeeks.where((w) => w.end.isBefore(today)).length;
      final change = p.nextChange;
      final daysTo = change?.start.difference(DateTime(today.year, today.month, today.day)).inDays;
      final inWords = daysTo == null
          ? ''
          : daysTo < 7
              ? 'in $daysTo ${daysTo == 1 ? 'day' : 'days'}'
              : 'in ${(daysTo / 7).round()} ${(daysTo / 7).round() == 1 ? 'week' : 'weeks'}';

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: theme.textTheme.bodySmall?.copyWith(color: fg)),
          Text(
            'Week ${p.week.number}',
            style: theme.textTheme.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.bold),
          ),
          Text('${p.term.name} · ${p.year.label} · ${phaseLabel(p.week.phase)}',
              style: theme.textTheme.titleSmall?.copyWith(color: fg)),
          Text('${d.format(p.week.start)} – ${d.format(p.week.end)}',
              style: theme.textTheme.bodySmall?.copyWith(color: fg)),
          if (p.week.phase != WeekPhase.trimesterBreak) ...[
            const SizedBox(height: 12),
            Semantics(
              label: '$done of ${termWeeks.length} weeks of the trimester done',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: termWeeks.isEmpty ? 0 : done / termWeeks.length,
                  minHeight: 6,
                  backgroundColor: fg.withValues(alpha: 0.15),
                  color: fg,
                ),
              ),
            ),
          ],
          if (change != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: fg),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${phaseLabel(change.phase)} from ${d.format(change.start)} ($inWords)',
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ],
          if (p.week.hasHoliday) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.celebration_outlined, size: 18, color: fg),
                const SizedBox(width: 6),
                Text('Public holiday this week', style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
              ],
            ),
          ],
        ],
      );
    }

    return TintedCard(color: scheme.primaryContainer, child: content);
  }
}
