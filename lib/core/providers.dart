import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/features/room_booking/data/booking_service.dart';
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
