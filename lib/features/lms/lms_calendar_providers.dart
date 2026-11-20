import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/updates.dart';
import 'package:resit/features/lms/lms_providers.dart';

/// How many days ahead the xSiTe calendar looks.
const lmsCalendarDays = 28;

/// The student's xSiTe calendar for the next [lmsCalendarDays] days, across
/// their active courses (one request for all of them). Kept until refreshed
/// or signed out.
final lmsCalendarProvider = FutureProvider<LmsAgenda>((ref) async {
  final service = ref.watch(lmsServiceProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = DateTime(from.year, from.month, from.day + lmsCalendarDays);
  final ids = [for (final c in activeCourses(await service.courses(), from)) c.orgUnitId];
  if (ids.isEmpty) return LmsAgenda(from, to, const []);
  return LmsAgenda(from, to, agenda(await service.calendar.events(ids, from, to), from, to));
});

/// What's new in each active course (unread discussions, new feedback,
/// quizzes to attempt), by xSiTe course id, in one request. Kept until the
/// course list is refreshed or signed out.
final lmsUpdatesProvider = FutureProvider<Map<String, CourseUpdates>>((ref) async {
  final service = ref.watch(lmsServiceProvider);
  final ids = [for (final c in activeCourses(await service.courses(), DateTime.now())) c.orgUnitId];
  if (ids.isEmpty) return const <String, CourseUpdates>{};
  return service.calendar.updates(ids);
});

/// What's new in one course (by xSiTe course id).
final lmsCourseUpdatesProvider = FutureProvider.family<CourseUpdates, String>(
    (ref, id) => ref.watch(lmsServiceProvider).calendar.courseUpdates(id));
