import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/in4sit/timetable_service.dart';
import 'package:resit/features/timetable/data/timetable_store.dart';
import 'package:resit/features/timetable/data/upcoming_classes.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/core/providers.dart';

final timetableServiceProvider = Provider<TimetableService>((ref) {
  return TimetableService(ref.watch(authServiceProvider), queue: ref.watch(in4SitQueueProvider));
});

/// The timetable weeks saved on the device, for instant and offline viewing.
final timetableWeekStoreProvider = Provider<TimetableWeekStore>((ref) => TimetableWeekStore());

final upcomingClassesServiceProvider = Provider<UpcomingClassesService>((ref) {
  return UpcomingClassesService(ref.watch(timetableServiceProvider));
});

/// The last saved list of upcoming classes, shown on Home straight away.
final savedUpcomingClassesProvider = FutureProvider<List<ClassSession>>((ref) {
  return ref.watch(upcomingClassesServiceProvider).saved();
});

/// When the saved upcoming classes were read from in4SIT ("Updated 2 h ago").
final upcomingClassesUpdatedProvider = FutureProvider<DateTime?>((ref) {
  ref.watch(upcomingClassesProvider);
  return ref.watch(upcomingClassesServiceProvider).savedAt();
});

/// Upcoming classes from in4SIT, read once per sign-in (invalidate to
/// re-read). Until it arrives, Home shows [savedUpcomingClassesProvider].
final upcomingClassesProvider = FutureProvider<List<ClassSession>>((ref) async {
  if (!ref.watch(authStateProvider)) return ref.watch(upcomingClassesServiceProvider).saved();
  return ref.watch(upcomingClassesServiceProvider).load();
});
