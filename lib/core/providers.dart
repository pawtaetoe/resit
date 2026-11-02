import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/totp.dart';
import 'package:resit/features/room_booking/data/booking_service.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/room_booking/data/quota.dart';
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

/// True while the app is quietly restoring the saved session at startup.
final sessionRestoringProvider = StateProvider<bool>((ref) => false);

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
