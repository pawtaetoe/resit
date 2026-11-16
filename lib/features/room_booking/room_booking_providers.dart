import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/rbs/booking_service.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/core/providers.dart';

final bookingServiceProvider = Provider<BookingService>((ref) {
  return BookingService(
    ref.watch(sessionClientProvider), 
    ref.watch(authServiceProvider)
  );
});

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
