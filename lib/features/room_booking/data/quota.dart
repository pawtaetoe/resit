import 'package:intl/intl.dart';
import 'package:resit/features/room_booking/data/models.dart';

/// Each student may book up to 4 hours a week per room type: 4 h of
/// discussion rooms and, separately, 4 h of meeting rooms.
const weeklyQuotaMinutes = 4 * 60;

const discussionRoom = 'Discussion Room';
const meetingRoom = 'Meeting Room';
const quotaRoomTypes = [discussionRoom, meetingRoom];

String roomTypeLabel(String type) => switch (type) {
      discussionRoom => 'Discussion rooms',
      meetingRoom => 'Meeting rooms',
      _ => type,
    };

/// Monday of the week [day] falls in (weeks run Monday to Sunday).
DateTime weekStart(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

String formatHours(int minutes) {
  if (minutes <= 0) return '0 h';
  if (minutes < 60) return '$minutes min';
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';
}

DateTime? bookingDate(Booking b) {
  try {
    return DateFormat('d MMM yyyy').parse(b.date.trim());
  } catch (_) {
    return null;
  }
}

/// When a booking starts (its date plus the start of "13:00-15:00").
DateTime? bookingStart(Booking b) {
  final date = bookingDate(b);
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(b.timeRange);
  if (date == null || m == null) return date;
  return DateTime(date.year, date.month, date.day, int.parse(m[1]!), int.parse(m[2]!));
}

/// Length of a booking from its "13:00-15:00" time range, or 0 if unreadable.
int bookingMinutes(Booking b) {
  final m = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(b.timeRange);
  if (m == null) return 0;
  final start = int.parse(m[1]!) * 60 + int.parse(m[2]!);
  final end = int.parse(m[3]!) * 60 + int.parse(m[4]!);
  return end > start ? end - start : 0;
}

/// Bookings that no longer hold the room don't use up quota.
bool countsTowardQuota(Booking b) {
  final s = b.status.toLowerCase();
  return !(s.contains('cancel') || s.contains('reject') || s.contains('withdraw') || s.contains('release'));
}

/// The room type of a booked room: looked up by name in the room list, with
/// a guess from the name as a fallback. Null when it can't be told.
String? roomTypeOf(String roomName, Map<String, String> typeByName) {
  final key = roomName.trim().toLowerCase();
  final known = typeByName[key];
  if (known != null) return known;
  if (key.contains('meeting') || RegExp(r'\bmr\b').hasMatch(key)) return meetingRoom;
  if (key.contains('discussion') || RegExp(r'\bdr\b').hasMatch(key)) return discussionRoom;
  return null;
}

/// The bookable room type a resource type name belongs to, matched by the
/// words in it so variants like "Meeting Rooms" or "MEETING ROOM (Hybrid)"
/// count too. Null for other kinds of resources.
String? canonicalRoomType(String typeName) {
  final t = typeName.toLowerCase();
  if (t.contains('discussion')) return discussionRoom;
  if (t.contains('meeting')) return meetingRoom;
  return null;
}

extension RoomQuotaType on Room {
  /// The type this room's weekly allowance is counted under.
  String get quotaType => canonicalRoomType(rsrcTypName) ?? rsrcTypName;
}

Map<String, String> typeByRoomName(Iterable<Room> rooms) => {
      for (final r in rooms) r.rsrcName.trim().toLowerCase(): r.quotaType,
    };

/// How much of each room type's weekly allowance is used in one week.
class WeeklyQuota {
  final DateTime week; // Monday
  final Map<String, int> usedMinutes;

  /// Bookings in this week whose room type couldn't be worked out.
  final int unknownBookings;

  const WeeklyQuota(this.week, this.usedMinutes, {this.unknownBookings = 0});

  factory WeeklyQuota.from(Iterable<Booking> bookings, DateTime day, Map<String, String> typeByName) {
    final week = weekStart(day);
    final nextWeek = DateTime(week.year, week.month, week.day + 7);
    final used = <String, int>{};
    var unknown = 0;
    final seen = <String>{};

    for (final b in bookings) {
      if (!countsTowardQuota(b)) continue;
      if (b.bookingRef.isNotEmpty && !seen.add(b.bookingRef)) continue;
      final date = bookingDate(b);
      if (date == null || date.isBefore(week) || !date.isBefore(nextWeek)) continue;
      final type = roomTypeOf(b.roomName, typeByName);
      if (type == null) {
        unknown++;
        continue;
      }
      used[type] = (used[type] ?? 0) + bookingMinutes(b);
    }
    return WeeklyQuota(week, used, unknownBookings: unknown);
  }

  int used(String type) => usedMinutes[type] ?? 0;

  int remaining(String type) {
    final left = weeklyQuotaMinutes - used(type);
    return left < 0 ? 0 : left;
  }

  bool fits(String type, int minutes) => minutes <= remaining(type);

  WeeklyQuota plus(String type, int minutes) =>
      WeeklyQuota(week, {...usedMinutes, type: used(type) + minutes}, unknownBookings: unknownBookings);
}
