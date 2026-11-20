import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

// A course's overview, checklists and surveys, by xSiTe course id, and the
// course files downloaded for opening. Kept once loaded until refreshed or
// signed out (see [clearCourseExtras]).

/// The course overview (syllabus), or null if the course has none.
final lmsOverviewProvider =
    FutureProvider.family<CourseOverview?, String>((ref, id) => ref.watch(lmsServiceProvider).extras.overview(id));

/// A course's checklists and surveys, read side by side. One tool being
/// closed to students leaves its list null; both closed is "not available".
final lmsChecklistsSurveysProvider = FutureProvider.family<ChecklistsAndSurveys, String>((ref, id) async {
  final extras = ref.watch(lmsServiceProvider).extras;
  Future<List<T>?> orNull<T>(Future<List<T>> f) =>
      f.then<List<T>?>((v) => v).catchError((Object e) => e is LmsUnavailableException ? null : throw e);
  final checklists = orNull(extras.checklists(id));
  final surveys = orNull(extras.surveys(id));
  await Future.wait([checklists, surveys]);
  final result = ChecklistsAndSurveys(checklists: await checklists, surveys: await surveys);
  if (result.checklists == null && result.surveys == null) throw LmsUnavailableException('checklists and surveys');
  return result;
});

/// Course files downloaded to open on the device.
final topicFilesProvider = Provider<TopicFiles>((ref) => TopicFiles(ref.watch(lmsServiceProvider).extras));

/// Forgets every course's overview, checklists and surveys, and deletes
/// downloaded files (on sign-out).
Future<void> clearCourseExtras(Ref ref) async {
  ref.invalidate(lmsOverviewProvider);
  ref.invalidate(lmsChecklistsSurveysProvider);
  await ref.read(topicFilesProvider).clear();
}
