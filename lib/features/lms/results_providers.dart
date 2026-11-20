import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/features/lms/lms_providers.dart';

/// An assignment or quiz in a course, by xSiTe course id and its own id.
typedef CourseItemKey = ({String orgUnitId, int id});

// Each of these reads its item from the course's list provider, so
// refreshing the course (or signing out, which drops the lists) drops these
// too. Kept once loaded, like the other course sections.

/// Your released feedback on an assignment, or null if none yet.
final assignmentFeedbackProvider = FutureProvider.family<AssignmentFeedback?, CourseItemKey>((ref, k) async {
  final list = await ref.watch(lmsAssignmentsProvider(k.orgUnitId).future);
  final a = list.where((a) => a.id == k.id).firstOrNull;
  if (a == null) return null;
  return ref.watch(lmsServiceProvider).feedback(a);
});

/// Your attempts at a quiz, first attempt first.
final quizAttemptsProvider = FutureProvider.family<List<QuizAttempt>, CourseItemKey>((ref, k) async {
  final list = await ref.watch(lmsQuizzesProvider(k.orgUnitId).future);
  final q = list.where((q) => q.id == k.id).firstOrNull;
  if (q == null) return const [];
  return ref.watch(lmsServiceProvider).quizAttempts(q);
});
