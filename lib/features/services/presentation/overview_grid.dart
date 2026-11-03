import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
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
        onTap: openProgress,
      ));
      if (record.cumulativeGpa != null) {
        // Hidden until the user taps the eye.
        tiles.add(_Tile(
          icon: Icons.grade_outlined,
          value: gradesVisible ? record.cumulativeGpa! : hiddenValue,
          caption: 'cumulative GPA'
              '${record.latestTermGpa != null ? ' · last term ${gradesVisible ? record.latestTermGpa : hiddenValue}' : ''}',
          semanticsLabel: gradesVisible ? null : 'Cumulative GPA, hidden',
          action: const GradeVisibilityButton(),
          onTap: openProgress,
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

    // Rows of tiles (two on a phone, three on wider screens); tiles in a
    // row share the tallest one's height, so captions of different lengths
    // don't leave the cards misaligned. A short last row spreads its tiles
    // across the full width.
    const gap = 8.0;
    return LayoutBuilder(builder: (context, constraints) {
      final perRow = constraints.maxWidth >= 600 ? 3 : 2;
      return Column(
        children: [
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

  /// A small button in the top-right corner (e.g. show/hide grades).
  final Widget? action;

  /// Read out instead of "value, caption" (e.g. when the value is hidden).
  final String? semanticsLabel;

  const _Tile({
    required this.icon,
    required this.value,
    required this.caption,
    this.onTap,
    this.action,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tile = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          label: semanticsLabel ?? '$value, $caption',
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
    if (action == null) return tile;
    // Over the corner, so the button doesn't make the tile taller.
    return Stack(children: [tile, Positioned(top: 4, right: 4, child: action!)]);
  }
}
