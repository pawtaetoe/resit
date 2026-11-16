import 'package:intl/intl.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';

/// When a booking starts, for ordering lists: its date plus the start of
/// its time range, the date alone if the time can't be read, or 1970 if the
/// date can't be read either.
DateTime bookingSortTime(Booking b) {
  final dateStr = b.date;
  final timeRangeStr = b.timeRange;
  try {
    final date = DateFormat('d MMM yyyy').parse(dateStr);
    if (timeRangeStr.contains('-')) {
      final parts = timeRangeStr.split('-')[0].trim().split(':');
      if (parts.length == 2) {
        return date.add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
      }
    }
    return date;
  } catch (_) {
    try {
      return DateFormat('d MMM yyyy').parse(dateStr);
    } catch (_) {
      return DateTime(1970);
    }
  }
}

/// The upcoming list: confirmed bookings among [current], soonest first
/// (that's the one you need next).
List<Booking> upcomingBookings(List<Booking> current) {
  final list = current.where((b) => b.status.toLowerCase() == 'confirmed').toList();
  list.sort((a, b) => bookingSortTime(a).compareTo(bookingSortTime(b)));
  return list;
}

/// The past list: [history] plus [current] bookings that are no longer
/// confirmed, one per booking reference, newest first.
List<Booking> pastBookings(List<Booking> history, List<Booking> current) {
  final combined = <String, Booking>{};
  for (final b in history) {
    combined[b.bookingRef] = b;
  }
  for (final b in current.where((b) => b.status.toLowerCase() != 'confirmed')) {
    combined[b.bookingRef] = b;
  }
  return combined.values.toList()..sort((a, b) => bookingSortTime(b).compareTo(bookingSortTime(a)));
}
