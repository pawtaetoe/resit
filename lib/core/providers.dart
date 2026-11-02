import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/auth/totp.dart';
import 'package:resit/features/room_booking/data/booking_service.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/room_booking/data/quota.dart';
import 'package:resit/features/calendar/data/academic_calendar.dart';
import 'package:resit/features/exams/data/academic_record.dart';
import 'package:resit/features/exams/data/exam_service.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});

final sessionClientProvider = Provider<SessionClient>((ref) {
  return SessionClient();
});

final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(sessionClientProvider);
  final service = AuthService(client, ref.watch(secureStorageProvider));
  // Keep the UI's signed-in flag in sync when the keep-alive finds the
  // session has expired (or gets restored).
  service.onSessionChanged = (active) {
    ref.read(authStateProvider.notifier).state = active;
  };
  ref.onDispose(service.dispose);
  return service;
});

final bookingServiceProvider = Provider<BookingService>((ref) {
  return BookingService(
    ref.watch(sessionClientProvider), 
    ref.watch(authServiceProvider)
  );
});

final timetableServiceProvider = Provider<TimetableService>((ref) {
  return TimetableService(ref.watch(authServiceProvider));
});

// A provider to manage the login state globally
final authStateProvider = StateProvider<bool>((ref) => false);

/// Checks the session and signs in again automatically when it has expired.
final sessionControllerProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.watch(authServiceProvider), ref.watch(secureStorageProvider));
});

/// True while the app is checking the session or signing back in.
final sessionRestoringProvider = Provider<bool>((ref) => ref.watch(sessionControllerProvider).busy);

/// Which bottom tab is showing (0 = Home, 1 = Account). Lets other screens
/// send the user to Account to sign in.
final homeTabProvider = StateProvider<int>((ref) => 0);

/// The student's bookings plus which room type each room is, used to work
/// out the weekly allowance (see quota.dart). Refetched whenever a screen
/// using it opens again; invalidate it after booking or cancelling.
final quotaDataProvider = FutureProvider.autoDispose<({List<Booking> bookings, Map<String, String> types})>((ref) async {
  final service = ref.watch(bookingServiceProvider);
  final rooms = await service.getRooms();
  final bookings = await service.getQuotaBookings();
  return (bookings: bookings, types: typeByRoomName(rooms));
});

/// Allowance used in the week containing [day], or null while loading or if
/// it couldn't be loaded.
WeeklyQuota? weeklyQuotaFor(WidgetRef ref, DateTime day) {
  final data = ref.watch(quotaDataProvider).valueOrNull;
  if (data == null) return null;
  return WeeklyQuota.from(data.bookings, day, data.types);
}

/// The saved authenticator secret for automatic verification codes, or null
/// when not set up. Invalidate after saving or removing it.
final totpConfigProvider = FutureProvider<TotpConfig?>((ref) async {
  final saved = await ref.watch(secureStorageProvider).getTotp();
  if (saved == null || saved.isEmpty) return null;
  try {
    return TotpConfig.parse(saved);
  } catch (_) {
    return null;
  }
});

final examServiceProvider = Provider<ExamService>((ref) {
  return ExamService(ref.watch(authServiceProvider));
});

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

/// The next confirmed room booking that hasn't ended yet, for Home. Null when
/// signed out or there's none. Invalidate after booking or cancelling.
final nextBookingProvider = FutureProvider.autoDispose<Booking?>((ref) async {
  if (!ref.watch(authStateProvider)) return null;
  final bookings = await ref.watch(bookingServiceProvider).getBookings(bookingStatus: 'current');
  final now = DateTime.now();
  Booking? next;
  DateTime? nextStart;
  for (final b in bookings) {
    if (b.status.toLowerCase() != 'confirmed') continue;
    final start = bookingStart(b);
    if (start == null) continue;
    final end = start.add(Duration(minutes: bookingMinutes(b)));
    if (end.isBefore(now)) continue;
    if (nextStart == null || start.isBefore(nextStart)) {
      next = b;
      nextStart = start;
    }
  }
  return next;
});

final academicRecordServiceProvider = Provider<AcademicRecordService>((ref) {
  return AcademicRecordService(ref.watch(examServiceProvider));
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

/// The graduation date the user set on Home, if any.
final graduationDateProvider = FutureProvider<DateTime?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt('graduation_date');
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
});
