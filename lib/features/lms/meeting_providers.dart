import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/timetable/data/module_colours.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

/// The xSiTe course for a timetable module ("INF 2004" is "INF2004" on
/// xSiTe): the newest one that can be opened, as [courses] are newest first.
LmsCourse? courseForModule(List<LmsCourse> courses, String moduleCode) {
  final key = moduleKey(moduleCode);
  LmsCourse? fallback;
  for (final c in courses) {
    if (moduleKey(c.courseCode) != key) continue;
    if (c.canAccess && c.isActive) return c;
    fallback ??= c.canAccess ? c : null;
  }
  return fallback;
}

/// The newest meeting link posted in a module's xSiTe announcements, by
/// timetable module code ("INF 2004"); null if there's none. Reuses the
/// course list and the course's announcements when already read, else
/// reads just those (a request or two). Kept until refreshed or signed out.
final moduleMeetingLinkProvider = FutureProvider.family<MeetingLink?, String>((ref, moduleCode) async {
  final course = courseForModule(await ref.watch(lmsServiceProvider).courses(), moduleCode);
  if (course == null) return null;
  try {
    return latestMeetingLink(await ref.watch(lmsAnnouncementsProvider(course.orgUnitId).future));
  } on LmsUnavailableException {
    return null;
  }
});
