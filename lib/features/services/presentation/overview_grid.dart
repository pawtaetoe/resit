import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/calendar/data/academic_calendar.dart';
import 'package:resit/features/calendar/presentation/academic_calendar_screen.dart';
import 'package:resit/features/exams/presentation/academic_progress_screen.dart';
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

  /// Change or clear a graduation date already set.
  Future<void> _editGraduation(BuildContext context, WidgetRef ref, DateTime current) async {
    final choice = await showChoiceSheet<String>(
      context,
      icon: Icons.workspace_premium_outlined,
      title: 'Graduation date',
      message: DateFormat('d MMMM yyyy').format(current),
      choices: const [
        SheetChoice('change', 'Change date', icon: Icons.edit_calendar_outlined, primary: true),
        SheetChoice('clear', 'Remove the countdown', icon: Icons.delete_outline, danger: true),
      ],
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'change') return _setGraduation(context, ref, current);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('graduation_date');
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

    // Graduation: set by the user, since nothing in in4SIT says when. Until
    // then it's a button, not a tile, so it doesn't read as data.
    if (graduation != null) {
      tiles.add(StatTile(
        icon: Icons.workspace_premium_outlined,
        value: _days(graduation.difference(today).inDays),
        caption: 'to graduation (${DateFormat('MMM yyyy').format(graduation)})',
        onTap: () => _editGraduation(context, ref, graduation),
      ));
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
                label: const Text('Set graduation date for a countdown'),
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
