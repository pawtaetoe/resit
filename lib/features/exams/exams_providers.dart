import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/exams/data/academic_record_service.dart';
import 'package:resit/features/exams/data/exam_results_repository.dart';
import 'package:resit/sites/in4sit/exam_service.dart';
import 'package:resit/features/exams/domain/academic_record.dart';
import 'package:resit/core/providers.dart';

final examServiceProvider = Provider<ExamService>((ref) {
  return ExamService(ref.watch(authServiceProvider), queue: ref.watch(in4SitQueueProvider));
});

final examResultsRepositoryProvider = Provider<ExamResultsRepository>((ref) {
  return ExamResultsRepository(ref.watch(examServiceProvider));
});

final academicRecordServiceProvider = Provider<AcademicRecordService>((ref) {
  return AcademicRecordService(ref.watch(examResultsRepositoryProvider));
});

/// The last saved academic record, shown straight away on Home.
final savedAcademicRecordProvider = FutureProvider<AcademicRecord?>((ref) {
  return ref.watch(academicRecordServiceProvider).saved();
});

/// The academic record, re-read from in4SIT at most once a day while signed
/// in. Until it arrives, Home shows [savedAcademicRecordProvider].
final academicRecordProvider = FutureProvider<AcademicRecord?>((ref) async {
  if (!ref.watch(authStateProvider)) return ref.watch(academicRecordServiceProvider).saved();
  return ref.watch(academicRecordServiceProvider).load();
});
