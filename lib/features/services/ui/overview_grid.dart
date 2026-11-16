import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/features/exams/exams_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:resit/features/calendar/ui/academic_calendar_screen.dart';
import 'package:resit/features/exams/ui/academic_progress_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Home dashboard: countdowns from SIT's academic calendar, credits and
/// GPA from the result slips, and days to the last day of school (the last day of finals). Each tile opens where
/// its number comes from.
class OverviewGrid extends ConsumerWidget {
  const OverviewGrid({super.key});

  void _open(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// Pick the graduation year (students rarely know the exact day): the
  /// countdown then runs to the Friday ending Trimester 3 finals that year.
  Future<void> _setGraduation(BuildContext context, WidgetRef ref, int? current) async {
    final now = DateTime.now();
    // A year whose graduation day has passed can't be picked.
    final first = graduationDay(now.year, ref.read(academicCalendarProvider).valueOrNull).date.isBefore(now)
        ? now.year + 1
        : now.year;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.page),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('When do you finish?', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Pick the year of your last trimester. The countdown runs to the last day of finals in '
                  'Trimester 3 that year (July or August), from SIT\'s academic calendar.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: Space.page),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var y = first; y <= first + 5; y++)
                      ChoiceChip(
                        label: Text('$y'),
                        selected: y == current,
                        onSelected: (_) => Navigator.pop(context, y),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('graduation_year', picked);
    await prefs.remove('graduation_date');
    ref.invalidate(graduationYearProvider);
  }

  /// Change or clear the graduation year.
  Future<void> _editGraduation(BuildContext context, WidgetRef ref, int year, DateTime date, bool estimated) async {
    final choice = await showChoiceSheet<String>(
      context,
      icon: Icons.workspace_premium_outlined,
      title: 'Finishing in $year',
      message: 'Counting down to ${DateFormat('EEEE d MMMM yyyy').format(date)}, your last day of finals '
          '(the end of Trimester 3 finals)'
          '${estimated ? ' (estimated: SIT\'s calendar doesn\'t list $year yet)' : ''}.',
      choices: const [
        SheetChoice('change', 'Change year', icon: Icons.edit_calendar_outlined, primary: true),
        SheetChoice('clear', 'Remove the countdown', icon: Icons.delete_outline, danger: true),
      ],
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'change') return _setGraduation(context, ref, year);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('graduation_year');
    await prefs.remove('graduation_date');
    ref.invalidate(graduationYearProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateUtils.dateOnly(DateTime.now());
    final calendar = ref.watch(academicCalendarProvider).valueOrNull;
    final position = calendar?.positionOf(today);
    final recordAsync = ref.watch(academicRecordProvider);
    final record = recordAsync.valueOrNull ?? ref.watch(savedAcademicRecordProvider).valueOrNull;
    final signedIn = ref.watch(authStateProvider);
    final graduation = ref.watch(graduationProvider);
    final gradesVisible = ref.watch(gradesVisibleProvider);
    final d = DateFormat('d MMM');
    void openCalendar() => _open(context, const AcademicCalendarScreen());
    void openProgress() => _open(context, const AcademicProgressScreen());

    final tiles = <Widget>[];

    // Week of the trimester.
    if (position != null) {
      final weeks = position.term.termWeeks.length;
      tiles.add(StatTile(
        icon: Icons.calendar_view_week_outlined,
        value: 'Week ${position.week.number}',
        caption: position.week.phase == WeekPhase.study
            ? 'of $weeks · ${position.term.name}'
            : '${phaseLabel(position.week.phase)} · ${position.term.name}',
        onTap: openCalendar,
      ));
    } else if (calendar?.nextTermAfter(today) case final next?) {
      tiles.add(StatTile(
        icon: Icons.calendar_view_week_outlined,
        value: _days(next.$2.start.difference(today).inDays),
        caption: 'to ${next.$2.name} (${d.format(next.$2.start)})',
        onTap: openCalendar,
      ));
    }

    if (calendar != null) {
      // Finals.
      if (calendar.nextWeekWhere(today, (w) => w.phase == WeekPhase.finals) case (_, final finals)?) {
        final inFinals = finals.contains(today);
        tiles.add(StatTile(
          icon: Icons.edit_note,
          value: inFinals ? 'Finals' : _days(finals.start.difference(today).inDays),
          caption: inFinals ? 'this week, until ${d.format(finals.end)}' : 'to finals (${d.format(finals.start)})',
          onTap: openCalendar,
        ));
      }

      // Next break: recess or trimester break.
      final brk =
          calendar.nextWeekWhere(today, (w) => w.phase == WeekPhase.recess || w.phase == WeekPhase.trimesterBreak);
      if (brk != null) {
        final (term, week) = brk;
        final onBreak = week.contains(today);
        // A trimester break runs over several weeks; show when it ends.
        final breakEnd = term.weeks.where((w) => w.phase == week.phase && !w.start.isBefore(week.start)).last.end;
        tiles.add(StatTile(
          icon: Icons.beach_access_outlined,
          value: onBreak ? 'On break' : _days(week.start.difference(today).inDays),
          caption: onBreak
              ? 'until ${d.format(breakEnd)}'
              : 'to ${phaseLabel(week.phase).toLowerCase()} (${d.format(week.start)})',
          onTap: openCalendar,
        ));
      }

      // Public holidays are marked per week in SIT's calendar, not per day.
      if (calendar.nextWeekWhere(today, (w) => w.hasHoliday) case (_, final week)?) {
        final thisWeek = week.contains(today);
        tiles.add(StatTile(
          icon: Icons.celebration_outlined,
          value: thisWeek ? 'This week' : _days(week.start.difference(today).inDays),
          caption: thisWeek ? 'has a public holiday' : 'to a public holiday week (${d.format(week.start)})',
          onTap: openCalendar,
        ));
      }
    }

    // Credits and GPA from the result slips.
    if (record != null) {
      String n(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
      tiles.add(StatTile(
        icon: Icons.school_outlined,
        value: n(record.creditsEarned),
        caption: 'credits earned'
            '${record.creditsInProgress > 0 ? ' · ${n(record.creditsInProgress)} in progress' : ''}',
        onTap: openProgress,
      ));
      if (record.cumulativeGpa != null) {
        // Hidden until the user taps the eye.
        tiles.add(StatTile(
          icon: Icons.grade_outlined,
          value: gradesVisible ? record.cumulativeGpa! : hiddenValue,
          caption: 'cumulative GPA'
              '${record.latestTermGpa != null ? ' · last term ${gradesVisible ? record.latestTermGpa : hiddenValue}' : ''}',
          semanticsLabel: gradesVisible ? null : 'Cumulative GPA, hidden',
          onTap: openProgress,
        ));
      }
    } else if (signedIn && recordAsync.isLoading) {
      tiles.add(const StatTile(icon: Icons.school_outlined, value: '…', caption: 'adding up your credits'));
    }


    // Rows of tiles (two on a phone, three on wider screens); tiles in a
    // row share the tallest one's height, so captions of different lengths
    // don't leave the cards misaligned. A short last row spreads its tiles
    // across the full width.
    const gap = Space.card;
    final showsGpa = record?.cumulativeGpa != null;
    return LayoutBuilder(builder: (context, constraints) {
      final perRow = constraints.maxWidth >= 600 ? 3 : 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The show/hide-grades eye sits in the heading, not on the GPA tile,
          // so a near miss can't open Academic progress instead.
          SectionLabel('Overview', trailing: showsGpa ? const GradeVisibilityButton() : null),
          // Graduation: a countdown ring once a year is set.
          if (graduation != null) ...[
            GraduationRing(
              date: graduation.date,
              estimated: graduation.estimated,
              start: _programmeStart(record?.admitTerm, graduation.date),
              onTap: () => _editGraduation(context, ref, graduation.year, graduation.date, graduation.estimated),
            ),
            const SizedBox(height: gap),
          ],
          for (var i = 0; i < tiles.length; i += perRow) ...[
            if (i > 0) const SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = i; j < i + perRow && j < tiles.length; j++) ...[
                    if (j > i) const SizedBox(width: gap),
                    Expanded(child: tiles[j]),
                  ],
                ],
              ),
            ),
          ],
          if (graduation == null) ...[
            const SizedBox(height: gap),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _setGraduation(context, ref, null),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Set your final year for a countdown to your last day of school'),
              ),
            ),
          ],
        ],
      );
    });
  }
}

String _days(int days) => switch (days) {
      <= 0 => 'Today',
      1 => '1 day',
      _ => '$days days',
    };

/// When the programme started, for the ring's "how far along": September of
/// the admit term's first year ("AY2024/25 Trimester 1" → Sep 2024). Without
/// one, assume a three-year programme.
DateTime _programmeStart(String? admitTerm, DateTime graduation) {
  final year = admitTerm == null ? null : RegExp(r'(20\d{2})').firstMatch(admitTerm)?.group(1);
  if (year != null) return DateTime(int.parse(year), 9, 1);
  return DateTime(graduation.year - 3, 9, 1);
}

/// Days to the last day of school (the last day of finals) in the middle of a ring that fills as time passes,
/// from the start of the programme to graduation day.
class GraduationRing extends StatelessWidget {
  final DateTime date;
  final DateTime start;
  final bool estimated;
  final VoidCallback onTap;

  const GraduationRing({
    super.key,
    required this.date,
    required this.start,
    required this.estimated,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onPrimaryContainer;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = date.difference(today).inDays;
    final total = date.difference(start).inDays;
    final done = total <= 0 ? 1.0 : (today.difference(start).inDays / total).clamp(0.0, 1.0);
    final ringSize = MediaQuery.textScalerOf(context).scale(96).clamp(96.0, 140.0);
    final caption = days <= 0
        ? 'Finals are over!'
        : '${(done * 100).round()}% of the way · last final ${DateFormat('EEE d MMM yyyy').format(date)}'
            '${estimated ? ' (estimated)' : ''}';

    return Semantics(
      button: true,
      label: days <= 0 ? 'Finals are over' : '$days days to the last day of school, $caption',
      excludeSemantics: true,
      child: TintedCard(
        color: scheme.primaryContainer,
        onTap: onTap,
        child: Row(
          children: [
            SizedBox.square(
              dimension: ringSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: done,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: scheme.primary,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          child: Text(days <= 0 ? '🎓' : '$days',
                              style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                        ),
                        if (days > 0) Text(days == 1 ? 'day' : 'days', style: theme.textTheme.labelSmall?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.inset),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('to last day of school', style: theme.textTheme.titleMedium?.copyWith(color: fg)),
                  const SizedBox(height: 4),
                  Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: fg),
          ],
        ),
      ),
    );
  }
}
