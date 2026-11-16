import 'dart:convert';

import 'package:resit/sites/in4sit/timetable_service.dart';
import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/features/timetable/domain/class_session.dart';

/// The classes still to come, read from the in4SIT timetable, with a saved
/// copy (encrypted on the device) so Home can show the next class straight
/// away (and offline).
class UpcomingClassesService {
  static const _key = 'upcoming_classes';

  /// Weeks to look ahead for the next class: covers recess and the weeks
  /// around public holidays without reading the whole trimester.
  static const weeksAhead = 3;

  /// A saved copy this recent that still has a class to come isn't read
  /// again (unless forced).
  static const freshFor = Duration(hours: 1);

  final TimetableService timetable;
  final PrivateStore _store;

  /// The clock, replaceable in tests.
  final DateTime Function() _now;

  UpcomingClassesService(this.timetable, {PrivateStore? store, DateTime Function()? now})
      : _store = store ?? PrivateStore(),
        _now = now ?? DateTime.now;

  /// The saved classes and when they were read (null for copies saved
  /// before that was recorded).
  Future<({List<ClassSession> sessions, DateTime? fetchedAt})?> _read() async {
    try {
      final raw = await _store.read(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      // Older copies are a bare list.
      final list = json is Map ? json['sessions'] as List? ?? const [] : json as List;
      final at = json is Map ? (json['fetchedAt'] as num?)?.toInt() : null;
      return (
        sessions: [for (final j in list) classSessionFromJson((j as Map).cast<String, Object?>())],
        fetchedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ClassSession>> saved() async => (await _read())?.sessions ?? const [];

  /// When the saved copy was read from in4SIT, if known.
  Future<DateTime?> savedAt() async => (await _read())?.fetchedAt;

  /// Reads this week and, if no class is left to start in it, the weeks
  /// after it until one has a class (so during the week's last class there's
  /// still a next one). Skips in4SIT when the saved copy was read within
  /// [freshFor] and still has a class to come, unless [force]. Falls back to
  /// the saved copy if in4SIT can't be reached, without the classes that
  /// have ended (so it can be empty).
  Future<List<ClassSession>> load({bool force = false}) async {
    final now = _now();
    final copy = await _read();
    List<ClassSession> stillOn() => [
          for (final s in copy?.sessions ?? const <ClassSession>[])
            if (s.end.isAfter(now)) s
        ];

    final at = copy?.fetchedAt;
    if (!force &&
        at != null &&
        !at.isAfter(now) &&
        now.difference(at) < freshFor &&
        copy!.sessions.any((s) => s.start.isAfter(now))) {
      return stillOn();
    }

    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    try {
      final upcoming = <ClassSession>[];
      for (var i = 0; i < weeksAhead; i++) {
        final week = await timetable.week(DateTime(monday.year, monday.month, monday.day + i * 7));
        upcoming.addAll(week.sessions.where((s) => s.end.isAfter(now)));
        if (upcoming.any((s) => s.start.isAfter(now))) break;
      }
      upcoming.sort((a, b) => a.start.compareTo(b.start));
      try {
        await _store.write(
            _key,
            jsonEncode({
              'fetchedAt': now.millisecondsSinceEpoch,
              'sessions': [for (final s in upcoming) s.toJson()],
            }));
      } catch (_) {
        // Shown now; read again next time.
      }
      return upcoming;
    } catch (_) {
      // Never hand back classes that are all over: Home would keep asking
      // again for a list that can't help.
      if (copy != null) return stillOn();
      rethrow;
    }
  }

  Future<void> clear() async {
    try {
      await _store.delete(_key);
    } catch (_) {}
  }
}
