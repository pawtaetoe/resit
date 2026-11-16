import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:resit/sites/sit_website/academic_calendar_service.dart';

final academicCalendarServiceProvider = Provider<AcademicCalendarService>((ref) => AcademicCalendarService());

/// SIT's academic calendar (saved copy if fresh, otherwise fetched). Kept for
/// the app's lifetime; invalidate to re-check.
final academicCalendarProvider = FutureProvider<AcademicCalendar>((ref) {
  return ref.watch(academicCalendarServiceProvider).load();
});

/// Where today sits in the academic calendar, or null if unknown yet.
final todayInCalendarProvider = Provider<CalendarPosition?>((ref) {
  return ref.watch(academicCalendarProvider).valueOrNull?.positionOf(DateTime.now());
});

/// The graduation year the user set on Home, if any. (Older versions saved
/// a full date; its year is used.)
final graduationYearProvider = FutureProvider<int?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final year = prefs.getInt('graduation_year');
  if (year != null) return year;
  final ms = prefs.getInt('graduation_date');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms).year;
});

/// Graduation day from the year: the Friday ending Trimester 3 finals that
/// year, from SIT's calendar (or estimated when the calendar doesn't reach it).
final graduationProvider = Provider<({int year, DateTime date, bool estimated})?>((ref) {
  final year = ref.watch(graduationYearProvider).valueOrNull;
  if (year == null) return null;
  final day = graduationDay(year, ref.watch(academicCalendarProvider).valueOrNull);
  return (year: year, date: day.date, estimated: day.estimated);
});
