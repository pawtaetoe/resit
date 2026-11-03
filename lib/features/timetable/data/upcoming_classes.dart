import 'dart:convert';

import 'package:resit/features/timetable/data/timetable_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// When a class starts and ends, as date-times.
extension ClassSessionTimes on ClassSession {
  DateTime get start => date.add(Duration(minutes: startMin));
  DateTime get end => date.add(Duration(minutes: endMin));

  Map<String, Object?> toJson() => {
        'date': date.toIso8601String(),
        'course': courseCode,
        'section': section,
        'component': component,
        'start': startMin,
        'end': endMin,
        'location': location,
        'coinciding': coinciding,
      };
}

ClassSession classSessionFromJson(Map<String, Object?> j) => ClassSession(
      date: DateTime.parse(j['date'] as String),
      courseCode: j['course'] as String,
      section: j['section'] as String,
      component: j['component'] as String,
      startMin: j['start'] as int,
      endMin: j['end'] as int,
      location: j['location'] as String,
      coinciding: j['coinciding'] as bool? ?? false,
    );

/// The class on now and the next one to start after now; either can be
/// null. With overlapping classes, "now" is the one that started first.
({ClassSession? current, ClassSession? next}) currentAndNextClass(Iterable<ClassSession> sessions, DateTime now) {
  ClassSession? current;
  ClassSession? next;
  for (final s in sessions) {
    if (!s.end.isAfter(now)) continue;
    if (!s.start.isAfter(now)) {
      if (current == null || s.start.isBefore(current.start)) current = s;
    } else if (next == null || s.start.isBefore(next.start)) {
      next = s;
    }
  }
  return (current: current, next: next);
}

/// The classes still to come, read from the in4SIT timetable, with a saved
/// copy so Home can show the next class straight away (and offline).
class UpcomingClassesService {
  static const _key = 'upcoming_classes';

  /// Weeks to look ahead for the next class: covers recess and the weeks
  /// around public holidays without reading the whole trimester.
  static const weeksAhead = 3;

  final TimetableService timetable;

  UpcomingClassesService(this.timetable);

  Future<List<ClassSession>> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return [for (final j in jsonDecode(raw) as List) classSessionFromJson(j as Map<String, Object?>)];
    } catch (_) {
      return const [];
    }
  }

  /// Reads this week and, if no class is left to start in it, the weeks
  /// after it until one has a class (so during the week's last class there's
  /// still a next one). Falls back to the saved copy if in4SIT can't be
  /// reached.
  Future<List<ClassSession>> load() async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    try {
      final upcoming = <ClassSession>[];
      for (var i = 0; i < weeksAhead; i++) {
        final week = await timetable.week(DateTime(monday.year, monday.month, monday.day + i * 7));
        upcoming.addAll(week.sessions.where((s) => s.end.isAfter(now)));
        if (upcoming.any((s) => s.start.isAfter(now))) break;
      }
      upcoming.sort((a, b) => a.start.compareTo(b.start));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final s in upcoming) s.toJson()]));
      return upcoming;
    } catch (_) {
      final cached = await saved();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
