import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:resit/core/providers.dart';

final lmsServiceProvider = Provider<LmsService>((ref) => LmsService(ref.watch(authServiceProvider)));

// A course's activities, by xSiTe course id. Kept once loaded (so going back
// to a course is instant) until refreshed or signed out.
final lmsAnnouncementsProvider = FutureProvider.family<List<Announcement>, String>(
    (ref, id) => ref.watch(lmsServiceProvider).announcements(id));
final lmsAssignmentsProvider =
    FutureProvider.family<List<Assignment>, String>((ref, id) => ref.watch(lmsServiceProvider).assignments(id));
final lmsQuizzesProvider =
    FutureProvider.family<List<Quiz>, String>((ref, id) => ref.watch(lmsServiceProvider).quizzes(id));
final lmsGradesProvider =
    FutureProvider.family<CourseGrades, String>((ref, id) => ref.watch(lmsServiceProvider).grades(id));
final lmsGroupsProvider =
    FutureProvider.family<List<MyGroup>, String>((ref, id) => ref.watch(lmsServiceProvider).groups(id));

/// What's due soon in one course: assignments not yet submitted and quizzes,
/// read side by side. A course without either tool just has nothing due.
final lmsCourseDueProvider = FutureProvider.family<List<DueItem>, ({String id, String code})>((ref, c) async {
  Future<List<T>> orEmpty<T>(Future<List<T>> f) => f.catchError((Object e) => e is LmsUnavailableException ? <T>[] : throw e);
  final assignments = orEmpty(ref.watch(lmsAssignmentsProvider(c.id).future));
  final quizzes = orEmpty(ref.watch(lmsQuizzesProvider(c.id).future));
  // Both at once; the first real error (if any) is reported as is.
  await Future.wait([assignments, quizzes]);
  return dueSoon(c.code, await assignments, await quizzes, DateTime.now());
});

/// How far through a course's content (by xSiTe course id) the user is. Kept
/// until the course list is refreshed.
final lmsProgressProvider = FutureProvider.family<CourseProgress, String>((ref, orgUnitId) {
  return ref.watch(lmsServiceProvider).progress(orgUnitId);
});

/// A course's content (by xSiTe course id), folder by folder.
final lmsContentsProvider = FutureProvider.family<List<ContentModule>, String>((ref, orgUnitId) {
  return ref.watch(lmsServiceProvider).contents(orgUnitId);
});
