import 'dart:convert';

import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/sites/in4sit/timetable_service.dart';
import 'package:resit/features/timetable/data/upcoming_classes.dart';

/// A week as last read from in4SIT, and when.
class SavedWeek {
  final WeekSchedule week;
  final DateTime fetchedAt;

  SavedWeek(this.week, this.fetchedAt);
}

/// The timetable weeks last read from in4SIT, kept encrypted on the device
/// so the timetable opens at once and still works when in4SIT is slow or
/// down. Erased on sign-out.
class TimetableWeekStore {
  static const _key = 'timetable_weeks';

  /// Weeks kept: enough for the weeks around now, with the oldest-read
  /// dropped first.
  static const maxWeeks = 10;

  /// Weeks that ended this long before this week are dropped.
  static const keepPast = Duration(days: 14);

  final PrivateStore _store;
  final DateTime Function() _now;

  TimetableWeekStore({PrivateStore? store, DateTime Function()? now})
      : _store = store ?? PrivateStore(),
        _now = now ?? DateTime.now;

  static String _id(DateTime monday) =>
      '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';

  Future<Map<DateTime, SavedWeek>> load() async {
    try {
      final raw = await _store.read(_key);
      if (raw == null) return {};
      final json = (jsonDecode(raw) as Map).cast<String, Object?>();
      final result = <DateTime, SavedWeek>{};
      for (final MapEntry(:key, :value) in json.entries) {
        final parts = key.split('-').map(int.parse).toList();
        final monday = DateTime(parts[0], parts[1], parts[2]);
        final entry = (value as Map).cast<String, Object?>();
        final sessions = [
          for (final s in entry['sessions'] as List) classSessionFromJson((s as Map).cast<String, Object?>())
        ];
        result[monday] = SavedWeek(
          WeekSchedule(monday, sessions),
          DateTime.fromMillisecondsSinceEpoch((entry['fetchedAt'] as num).toInt()),
        );
      }
      return result;
    } catch (_) {
      // Unreadable (older format, storage unavailable): start afresh.
      return {};
    }
  }

  Future<void> _saving = Future.value();

  /// Saves [week] as read now. Saves run one after another, so a week and
  /// the look-ahead week saved together don't overwrite each other.
  Future<void> save(WeekSchedule week) => _saving = _saving.then((_) => _save(week));

  Future<void> _save(WeekSchedule week) async {
    final weeks = await load();
    weeks[week.monday] = SavedWeek(week, _now());

    final now = _now();
    final thisMonday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    weeks.removeWhere((monday, _) => monday.isBefore(thisMonday.subtract(keepPast)));
    if (weeks.length > maxWeeks) {
      final byAge = weeks.entries.toList()..sort((a, b) => b.value.fetchedAt.compareTo(a.value.fetchedAt));
      weeks
        ..clear()
        ..addEntries(byAge.take(maxWeeks));
    }

    try {
      await _store.write(
        _key,
        jsonEncode({
          for (final MapEntry(key: monday, value: saved) in weeks.entries)
            _id(monday): {
              'fetchedAt': saved.fetchedAt.millisecondsSinceEpoch,
              'sessions': [for (final s in saved.week.sessions) s.toJson()],
            },
        }),
      );
    } catch (_) {
      // Shown now; saved next time.
    }
  }

  /// Erases the saved weeks, after any save already under way.
  Future<void> clear() => _saving = _saving.then((_) async {
        try {
          await _store.delete(_key);
        } catch (_) {}
      });
}
