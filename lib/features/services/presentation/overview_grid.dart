import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/calendar/data/academic_calendar.dart';
import 'package:resit/features/calendar/presentation/academic_calendar_screen.dart';
import 'package:resit/features/exams/presentation/exam_results_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Home dashboard: countdowns from SIT's academic calendar, credits and
/// GPA from the result slips, and days to graduation. Each tile opens where
/// its number comes from.
class OverviewGrid extends ConsumerWidget {
  const OverviewGrid({super.key});

  void _open(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _setGraduation(BuildContext context, WidgetRef ref, DateTime? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Expected graduation date',
      initialDate: current ?? DateTime(now.year + 3, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('graduation_date', picked.millisecondsSinceEpoch);
    ref.invalidate(graduationDateProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateUtils.dateOnly(DateTime.now());
    final calendar = ref.watch(academicCalendarProvider).valueOrNull;
    final position = calendar?.positionOf(today);
    final recordAsync = ref.watch(academicRecordProvider);
    final record = recordAsync.valueOrNull ?? ref.watch(savedAcademicRecordProvider).valueOrNull;
    final signedIn = ref.watch(authStateProvider);
    final graduation = ref.watch(graduationDateProvider).valueOrNull;
    final d = DateFormat('d MMM');
    void openCalendar() => _open(context, const AcademicCalendarScreen());
    void openResults() => _open(context, const ExamResultsScreen());

    final tiles = <Widget>[];

    // Week of the trimester.
    if (position != null) {
      final weeks = position.term.termWeeks.length;
      tiles.add(_Tile(
        icon: Icons.calendar_view_week_outlined,
        value: 'Week ${position.week.number}',
        caption: position.week.phase == WeekPhase.study
            ? 'of $weeks · ${position.term.name}'
            : '${phaseLabel(position.week.phase)} · ${position.term.name}',
        onTap: openCalendar,
      ));
    } else if (calendar?.nextTermAfter(today) case final next?) {
      tiles.add(_Tile(
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
        tiles.add(_Tile(
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
        tiles.add(_Tile(
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
        tiles.add(_Tile(
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
      tiles.add(_Tile(
        icon: Icons.school_outlined,
        value: n(record.creditsEarned),
        caption: 'credits earned'
            '${record.creditsInProgress > 0 ? ' · ${n(record.creditsInProgress)} in progress' : ''}',
        onTap: openResults,
      ));
      if (record.cumulativeGpa != null) {
        tiles.add(_Tile(
          icon: Icons.grade_outlined,
          value: record.cumulativeGpa!,
          caption: 'cumulative GPA'
              '${record.latestTermGpa != null ? ' · last term ${record.latestTermGpa}' : ''}',
          onTap: openResults,
        ));
      }
    } else if (signedIn && recordAsync.isLoading) {
      tiles.add(const _Tile(icon: Icons.school_outlined, value: '…', caption: 'adding up your credits'));
    }

    // Graduation: set by the user, since nothing in in4SIT says when.
    tiles.add(graduation == null
        ? _Tile(
            icon: Icons.workspace_premium_outlined,
            value: 'Set date',
            caption: 'to count down to graduation',
            onTap: () => _setGraduation(context, ref, null),
          )
        : _Tile(
            icon: Icons.workspace_premium_outlined,
            value: _days(graduation.difference(today).inDays),
            caption: 'to graduation (${DateFormat('MMM yyyy').format(graduation)})',
            onTap: () => _setGraduation(context, ref, graduation),
          ));

    return LayoutBuilder(builder: (context, constraints) {
      const gap = 8.0;
      final width = (constraints.maxWidth - gap) / 2;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < tiles.length; i++)
            SizedBox(
              // A leftover tile at the end spans the full width.
              width: tiles.length.isOdd && i == tiles.length - 1 ? constraints.maxWidth : width,
              child: tiles[i],
            ),
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

class _Tile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String caption;
  final VoidCallback? onTap;

  const _Tile({required this.icon, required this.value, required this.caption, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          label: '$value, $caption',
          button: onTap != null,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
