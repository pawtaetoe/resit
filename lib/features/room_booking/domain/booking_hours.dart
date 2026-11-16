import 'package:resit/features/room_booking/domain/rooms.dart';

/// Booking hours offered by RBS, in minutes since midnight.
const bookingOpenMin = 7 * 60;
const bookingCloseMin = 22 * 60;

/// The lengths a booking can have, in minutes.
const bookingLengths = [30, 60, 90, 120, 180, 240];

/// How many days ahead a room can be booked.
const bookingDaysAhead = 14;

/// [minutes] since midnight as "HH:mm".
String hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// A booking length for people: "30 min", "1 h", "1.5 h".
String durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';
}

int _toMin(String time) {
  final parts = time.trim().split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// Returns the slots covering the whole requested range, or an empty list if
/// any part of it is taken or missing. E.g. 13:00-14:00 needs both
/// 13:00-13:30 and 13:30-14:00 to be available.
List<RoomSlot> slotsInRange(List<RoomSlot> slots, int lo, int hi) {
  if (hi <= lo) return [];

  final inRange = <({RoomSlot slot, int start, int end})>[];
  for (final sl in slots) {
    try {
      final parts = sl.label.split('-');
      final s = _toMin(parts[0]);
      final e = _toMin(parts[1]);
      if (s >= lo && e <= hi) inRange.add((slot: sl, start: s, end: e));
    } catch (_) {
      // ignore malformed labels
    }
  }
  inRange.sort((a, b) => a.start.compareTo(b.start));

  // Slots must be available and run back-to-back from lo to hi.
  var cursor = lo;
  for (final s in inRange) {
    if (!s.slot.available || s.start != cursor) return [];
    cursor = s.end;
  }
  if (cursor != hi) return [];
  return inRange.map((s) => s.slot).toList();
}

/// First bookable half hour on [day] (a date at midnight), or null if none
/// are left, given that it's [now].
int? earliestStart(DateTime day, DateTime now) {
  var earliest = bookingOpenMin;
  if (day == DateTime(now.year, now.month, now.day)) {
    final nowMin = now.hour * 60 + now.minute;
    earliest = ((nowMin + 29) ~/ 30) * 30; // round up to the next half hour
    if (earliest < bookingOpenMin) earliest = bookingOpenMin;
  }
  return earliest <= bookingCloseMin - 30 ? earliest : null;
}

/// Every half hour a booking on [day] can still start at.
List<int> startOptions(DateTime day, DateTime now) {
  final first = earliestStart(day, now);
  if (first == null) return [];
  return [for (var m = first; m <= bookingCloseMin - 30; m += 30) m];
}

/// The booking lengths that end by closing time when starting at [startMin].
List<int> validDurations(int startMin) => bookingLengths.where((d) => startMin + d <= bookingCloseMin).toList();
