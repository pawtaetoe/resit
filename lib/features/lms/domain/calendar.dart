import 'package:resit/features/lms/domain/courses.dart';

/// What a calendar event on xSiTe is about, from the item it's tied to.
enum LmsEventKind { assignment, quiz, content, discussion, checklist, grade, survey, event }

/// How an event repeats (only daily and weekly repeats are spread over the
/// agenda; others show once, on their own date).
class LmsRecurrence {
  /// 1 none, 2 daily, 3 weekly, 4 monthly, 5 yearly (Brightspace's REPEAT_T).
  final int type;
  final int every;

  /// Weekdays it falls on (DateTime.monday..sunday), for weekly repeats.
  final Set<int> weekdays;
  final DateTime? until;

  const LmsRecurrence({required this.type, this.every = 1, this.weekdays = const {}, this.until});

  bool get isDaily => type == 2;
  bool get isWeekly => type == 3;
}

/// One event in the student's xSiTe calendar: a due date, an availability
/// window, a class event an instructor added, ...
class LmsEvent {
  final String orgUnitId;
  final int id;
  final String title;
  final String description;

  /// As xSiTe names the course ("INF2004-Embedded Systems Programming [...]")
  /// and its code ("SIT-2610-INF2004").
  final String courseName;
  final String courseCodeField;

  /// Local time; for an all-day event, midnight of its first day.
  final DateTime start;

  /// Local time; for an all-day event, midnight after its last day.
  final DateTime? end;
  final bool allDay;
  final String location;
  final LmsEventKind kind;

  /// Where it opens: the item it's tied to, else its calendar page (always
  /// https on xSiTe).
  final Uri url;
  final LmsRecurrence? recurrence;

  LmsEvent({
    required this.orgUnitId,
    required this.id,
    required this.title,
    required this.start,
    required this.url,
    this.description = '',
    this.courseName = '',
    this.courseCodeField = '',
    this.end,
    this.allDay = false,
    this.location = '',
    this.kind = LmsEventKind.event,
    this.recurrence,
  });

  /// "INF2004", read the same way as a course's.
  String get courseCode =>
      LmsCourse(orgUnitId: orgUnitId, name: courseName, code: courseCodeField, semester: '').courseCode;

  /// A due date or a point in time rather than a span.
  bool get isInstant => !allDay && (end == null || !end!.isAfter(start));

  LmsEvent at(DateTime newStart) => LmsEvent(
        orgUnitId: orgUnitId,
        id: id,
        title: title,
        start: newStart,
        url: url,
        description: description,
        courseName: courseName,
        courseCodeField: courseCodeField,
        end: end?.add(newStart.difference(start)),
        allDay: allDay,
        location: location,
        kind: kind,
        recurrence: recurrence,
      );
}

/// Courses worth asking xSiTe's calendar and updates about: ones the student
/// can open that are active and not over before [from].
List<LmsCourse> activeCourses(Iterable<LmsCourse> courses, DateTime from) => [
      for (final c in courses)
        if (c.canAccess && c.isActive && (c.end == null || c.end!.isAfter(from))) c,
    ];

/// [e] and its daily or weekly repeats that start in [from, to).
Iterable<LmsEvent> occurrences(LmsEvent e, DateTime from, DateTime to) sync* {
  final r = e.recurrence;
  if (r == null || !(r.isDaily || r.isWeekly)) {
    yield e;
    return;
  }
  final until = r.until ?? to;
  final every = r.every < 1 ? 1 : r.every;
  // Day by day (calendar days, so the time of day survives DST changes).
  for (var i = 0; i < 400; i++) {
    final s = DateTime(e.start.year, e.start.month, e.start.day + i, e.start.hour, e.start.minute);
    if (!s.isBefore(to) || s.isAfter(until)) break;
    final bool hit;
    if (r.isDaily) {
      hit = i % every == 0;
    } else {
      final week = i ~/ 7;
      final days = r.weekdays.isEmpty ? {e.start.weekday} : r.weekdays;
      hit = week % every == 0 && days.contains(s.weekday);
    }
    final ends = e.end == null ? s : s.add(e.end!.difference(e.start));
    if (hit && (!s.isBefore(from) || ends.isAfter(from))) yield i == 0 ? e : e.at(s);
  }
}

/// One day in the agenda.
class AgendaDay {
  final DateTime day;
  final List<LmsEvent> events;
  AgendaDay(this.day, this.events);
}

/// Events (with their repeats) from [from] to [to], by day, soonest first.
/// One already under way at [from] is listed on [from]'s day. On a day,
/// all-day events come first, then by time, then by course.
List<AgendaDay> agenda(Iterable<LmsEvent> events, DateTime from, DateTime to) {
  final firstDay = DateTime(from.year, from.month, from.day);
  final byDay = <DateTime, List<LmsEvent>>{};
  final seen = <(int, DateTime)>{};
  for (final e in events) {
    for (final o in occurrences(e, from, to)) {
      final ends = o.end ?? o.start;
      if (!o.start.isBefore(to) || (o.start.isBefore(from) && !ends.isAfter(from))) continue;
      if (!seen.add((o.id, o.start))) continue;
      final d = DateTime(o.start.year, o.start.month, o.start.day);
      byDay.putIfAbsent(d.isBefore(firstDay) ? firstDay : d, () => []).add(o);
    }
  }
  final days = byDay.keys.toList()..sort();
  return [
    for (final d in days)
      AgendaDay(
          d,
          byDay[d]!
            ..sort((a, b) {
              if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
              final t = a.start.compareTo(b.start);
              return t != 0 ? t : a.courseCode.compareTo(b.courseCode);
            })),
  ];
}

/// The student's xSiTe calendar from [from] (midnight today) to [to].
class LmsAgenda {
  final DateTime from;
  final DateTime to;
  final List<AgendaDay> days;
  LmsAgenda(this.from, this.to, this.days);

  int get count => days.fold(0, (n, d) => n + d.events.length);

  /// The next event (the first listed), if any.
  LmsEvent? get next => days.isEmpty ? null : days.first.events.first;

  /// Only one course's events.
  LmsAgenda forCourse(String orgUnitId) => LmsAgenda(from, to, [
        for (final d in days)
          if (d.events.where((e) => e.orgUnitId == orgUnitId).toList() case final events when events.isNotEmpty)
            AgendaDay(d.day, events),
      ]);
}
