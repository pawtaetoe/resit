/// One class meeting on a specific date.
class ClassSession {
  final DateTime date; // date only
  final String courseCode; // e.g. "CSC 2101"
  final String section; // e.g. "L1", "P2", "ALL"
  final String component; // Lectorial, Laboratory, ...
  final int startMin;
  final int endMin;
  final String location;

  /// ADFS/in4sit flags this when another class overlaps in time.
  final bool coinciding;

  ClassSession({
    required this.date,
    required this.courseCode,
    required this.section,
    required this.component,
    required this.startMin,
    required this.endMin,
    required this.location,
    required this.coinciding,
  });

  static String formatMinutes(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String get timeLabel => '${formatMinutes(startMin)} - ${formatMinutes(endMin)}';
}

class WeekSchedule {
  final DateTime monday;
  final List<ClassSession> sessions;

  WeekSchedule(this.monday, this.sessions);

  List<ClassSession> forDay(int dayIndex) => sessions
      .where((s) => s.date == DateTime(monday.year, monday.month, monday.day + dayIndex))
      .toList();
}

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
