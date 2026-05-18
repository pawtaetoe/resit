import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/features/room_booking/data/booking_service.dart';

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});

final sessionClientProvider = Provider<SessionClient>((ref) {
  return SessionClient();
});

final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(sessionClientProvider);
  return AuthService(client);
});

final bookingServiceProvider = Provider<BookingService>((ref) {
  return BookingService(
    ref.watch(sessionClientProvider), 
    ref.watch(authServiceProvider)
  );
});

// A provider to manage the login state globally
final authStateProvider = StateProvider<bool>((ref) => false);
