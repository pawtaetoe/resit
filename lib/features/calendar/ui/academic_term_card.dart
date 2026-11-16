import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';

/// One trimester: its dates, recess and finals, opening to every week.
class AcademicTermCard extends StatelessWidget {
  final AcademicTerm term;
  final DateTime today;
  final bool initiallyExpanded;

  const AcademicTermCard({super.key, required this.term, required this.today, required this.initiallyExpanded});

  @override
  Widget build(BuildContext context) {
    final d = DateFormat('d MMM');
    final finals = term.weeks.where((w) => w.phase == WeekPhase.finals).firstOrNull;
    final recess = term.weeks.where((w) => w.phase == WeekPhase.recess).firstOrNull;
    final summary = [
      '${d.format(term.start)} – ${d.format(term.end)}',
      if (recess != null) 'recess ${d.format(recess.start)}',
      if (finals != null) 'finals ${d.format(finals.start)}',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text('${term.name} · ${term.start.year}', style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(summary),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [for (final w in term.weeks) _WeekRow(week: w, isNow: w.contains(today))],
      ),
    );
  }
}

/// One week of a trimester, highlighted when it's this week.
class _WeekRow extends StatelessWidget {
  final AcademicWeek week;
  final bool isNow;

  const _WeekRow({required this.week, required this.isNow});

  Tone get _tone => switch (week.phase) {
        WeekPhase.recess => Tone.info,
        WeekPhase.finals => Tone.danger,
        WeekPhase.trimesterBreak => Tone.success,
        _ => Tone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = DateFormat('d MMM');
    final holiday = [
      if (week.holidayWeekday) 'public holiday on a weekday',
      if (week.holidayWeekendOrMonday) 'public holiday on a weekend or Monday',
    ].join(' and ');

    return Semantics(
      label: 'Week ${week.number}, ${d.format(week.start)} to ${d.format(week.end)}, ${phaseLabel(week.phase)}'
          '${holiday.isEmpty ? '' : ', $holiday'}${isNow ? ', this week' : ''}',
      excludeSemantics: true,
      child: Container(
        color: isNow ? scheme.secondaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text('Wk ${week.number}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: isNow ? FontWeight.bold : null)),
            ),
            Expanded(
              child: Text('${d.format(week.start)} – ${d.format(week.end)}',
                  style: TextStyle(fontWeight: isNow ? FontWeight.bold : null)),
            ),
            // Spelled out, not an icon you'd have to long-press to understand.
            if (week.hasHoliday)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: holiday,
                  child: const StatusPill(label: 'PH', tone: Tone.warning, icon: Icons.celebration_outlined),
                ),
              ),
            if (week.phase != WeekPhase.study) StatusPill(label: phaseLabel(week.phase), tone: _tone),
          ],
        ),
      ),
    );
  }
}
