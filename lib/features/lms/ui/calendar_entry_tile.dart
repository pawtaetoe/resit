import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:resit/features/lms/ui/xsite_calendar_screen.dart';

/// "Next: INF2004 Lab test, Tue 25 Nov · 4 events in 4 weeks".
String _summary(LmsAgenda a, {required bool showCourse}) {
  final next = a.next;
  if (next == null) return 'Nothing in the next 4 weeks';
  final what = [if (showCourse && next.courseCode.isNotEmpty) next.courseCode, next.title].join(' ');
  final when = DateFormat('EEE d MMM').format(next.start.isBefore(a.from) ? a.from : next.start);
  return 'Next: $what, $when · ${a.count} event${a.count == 1 ? '' : 's'} in 4 weeks';
}

/// A card that opens the xSiTe calendar (all courses, or [course]'s),
/// saying what's next in it.
class CalendarEntryTile extends ConsumerWidget {
  /// Only this course's events, if given.
  final LmsCourse? course;
  const CalendarEntryTile({super.key, this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final id = course?.orgUnitId;
    final subtitle = ref.watch(lmsCalendarProvider).when(
          data: (a) => _summary(id == null ? a : a.forCourse(id), showCourse: id == null),
          loading: () => "Checking xSiTe's calendar…",
          error: (e, _) => e is LmsUnavailableException ? 'Not available' : 'Due dates and events, by day',
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => XsiteCalendarScreen(course: course))),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.event_outlined),
          ),
          title: Text('Calendar', style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
