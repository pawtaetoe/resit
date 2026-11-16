import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/features/timetable/ui/class_block.dart';
import 'package:resit/features/timetable/ui/class_details_sheet.dart';
import 'package:resit/features/timetable/ui/course_palette.dart';
import 'package:resit/features/timetable/ui/module_legend.dart';
import 'package:resit/features/timetable/ui/week_grid_layout.dart';

/// The week of [monday], Monday to Friday: the days across the top, which
/// colour is which module, then the hours down the side with each class at
/// its time (side by side where classes overlap) and a line at the time now.
/// Tapping a class shows its details. While [week] is null (not here yet)
/// the grid is empty.
class WeekGrid extends StatelessWidget {
  final DateTime monday;
  final WeekSchedule? week;
  final CoursePalette palette;

  const WeekGrid({super.key, required this.monday, required this.week, required this.palette});

  @override
  Widget build(BuildContext context) {
    final week = this.week;
    final today = DateTime.now();
    final sessions = week?.sessions ?? const <ClassSession>[];

    // An hour's height: grows with the user's text size, so class text fits.
    final hourHeight = MediaQuery.textScalerOf(context).scale(60).clamp(60.0, 132.0);
    final layout = WeekGridLayout.fit(sessions, hourHeight: hourHeight);

    return LayoutBuilder(builder: (context, constraints) {
      final colWidth = (constraints.maxWidth - WeekGridLayout.timeColumnWidth) / WeekGridLayout.dayCount;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final small = theme.textTheme.labelSmall;
      final muted = scheme.onSurfaceVariant;
      final nowDate = DateTime(today.year, today.month, today.day);
      final todayIndex = nowDate.difference(monday).inDays;
      final nowMin = today.hour * 60 + today.minute;
      final showNow = todayIndex >= 0 && todayIndex < WeekGridLayout.dayCount && layout.shows(nowMin);

      final header = Row(
        children: [
          const SizedBox(width: WeekGridLayout.timeColumnWidth),
          for (var d = 0; d < WeekGridLayout.dayCount; d++)
            _DayHeader(
              date: DateTime(monday.year, monday.month, monday.day + d),
              today: today,
              width: colWidth,
              showMonth: d == 0,
            ),
        ],
      );

      final grid = SizedBox(
        height: layout.height,
        child: Stack(
          children: [
            for (var h = layout.startHour; h <= layout.endHour; h++)
              Positioned(
                top: layout.hourTop(h),
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    SizedBox(
                      width: WeekGridLayout.timeColumnWidth,
                      child: Transform.translate(
                        offset: const Offset(0, -7),
                        child: Text(
                          '${h.toString().padLeft(2, '0')}:00',
                          textAlign: TextAlign.center,
                          style: small?.copyWith(color: muted),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(height: 1, color: scheme.outlineVariant)),
                  ],
                ),
              ),
            for (var d = 0; d < WeekGridLayout.dayCount; d++) ...[
              if (d > 0)
                Positioned(
                  left: WeekGridLayout.timeColumnWidth + d * colWidth,
                  top: 0,
                  bottom: 0,
                  child: VerticalDivider(width: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              if (week != null)
                for (final placed in WeekGridLayout.placeDay(week.forDay(d)))
                  _placeBlock(context, layout, placed,
                      left: WeekGridLayout.timeColumnWidth + d * colWidth, colWidth: colWidth),
            ],
            if (showNow)
              Positioned(
                left: WeekGridLayout.timeColumnWidth + todayIndex * colWidth - 4,
                width: colWidth + 4,
                top: layout.minuteTop(nowMin) - 4,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      CircleAvatar(radius: 4, backgroundColor: scheme.error),
                      Expanded(child: Container(height: 2, color: scheme.error)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

      return Column(
        children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: header),
          // Which colour is which module this week.
          if (sessions.isNotEmpty)
            ModuleLegend(codes: {for (final s in sessions) s.courseCode}.toList()..sort(), palette: palette),
          const Divider(height: 1),
          Expanded(
            child: Stack(
              children: [
                // Room at the top so the first hour's label isn't clipped.
                SingleChildScrollView(padding: const EdgeInsets.only(top: 10, bottom: 8), child: grid),
                if (week != null && week.sessions.isEmpty)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.free_breakfast_outlined, color: muted, size: 32),
                        const SizedBox(height: 8),
                        Text('No classes this week', style: theme.textTheme.titleSmall?.copyWith(color: muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// [placed]'s block in its day's column, which starts [left] and is
  /// [colWidth] wide.
  Widget _placeBlock(BuildContext context, WeekGridLayout layout, PlacedSession placed,
      {required double left, required double colWidth}) {
    final s = placed.session;
    final laneWidth = colWidth / placed.laneCount;
    return Positioned(
      left: left + placed.lane * laneWidth + 1,
      top: layout.minuteTop(s.startMin) + 1,
      width: laneWidth - 2,
      height: layout.blockHeight(s),
      child: ClassBlock(
        session: s,
        colour: palette.colourOf(s.courseCode),
        onTap: () => showClassDetails(context, s),
      ),
    );
  }
}

/// A day's column heading: the weekday, the date (circled today), and the
/// month under the first day and the 1st.
class _DayHeader extends StatelessWidget {
  final DateTime date;
  final DateTime today;
  final double width;

  /// Shows the month even when [date] isn't the 1st.
  final bool showMonth;

  const _DayHeader({required this.date, required this.today, required this.width, required this.showMonth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = theme.textTheme.labelSmall;
    final muted = scheme.onSurfaceVariant;
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Text(DateFormat('E').format(date), style: small?.copyWith(color: isToday ? scheme.primary : muted)),
          const SizedBox(height: 2),
          CircleAvatar(
            radius: 13,
            backgroundColor: isToday ? scheme.primary : Colors.transparent,
            child: Text(
              '${date.day}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isToday ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
          if (date.day == 1 || showMonth) Text(DateFormat('MMM').format(date), style: small?.copyWith(color: muted)),
        ],
      ),
    );
  }
}
