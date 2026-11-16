import 'dart:convert';


/// What a week of the trimester is for, from the calendar's Schedule column.
enum WeekPhase { study, recess, finals, trimesterBreak, other }

String phaseLabel(WeekPhase phase) => switch (phase) {
      WeekPhase.study => 'Study week',
      WeekPhase.recess => 'Recess week',
      WeekPhase.finals => 'Final assessment',
      WeekPhase.trimesterBreak => 'Trimester break',
      WeekPhase.other => 'Week',
    };

/// One row of the calendar for one trimester.
class AcademicWeek {
  final int number;
  final WeekPhase phase;

  /// The Schedule text as SIT wrote it, e.g. "Study Weeks".
  final String schedule;
  final DateTime start; // date only
  final DateTime end; // date only, inclusive

  /// Marked `^`: a public holiday falls on a weekend or Monday this week.
  final bool holidayWeekendOrMonday;

  /// Marked `*`: a public holiday falls on a weekday this week.
  final bool holidayWeekday;

  const AcademicWeek({
    required this.number,
    required this.phase,
    required this.schedule,
    required this.start,
    required this.end,
    this.holidayWeekendOrMonday = false,
    this.holidayWeekday = false,
  });

  bool get hasHoliday => holidayWeekendOrMonday || holidayWeekday;

  Map<String, Object?> toJson() => {
        'number': number,
        'phase': phase.name,
        'schedule': schedule,
        'start': _day(start),
        'end': _day(end),
        if (holidayWeekendOrMonday) 'holidayWeekendOrMonday': true,
        if (holidayWeekday) 'holidayWeekday': true,
      };

  factory AcademicWeek.fromJson(Map<String, Object?> j) => AcademicWeek(
        number: (j['number'] as num).toInt(),
        phase: WeekPhase.values.asNameMap()[j['phase']] ?? WeekPhase.other,
        schedule: j['schedule'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        holidayWeekendOrMonday: j['holidayWeekendOrMonday'] == true,
        holidayWeekday: j['holidayWeekday'] == true,
      );

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

class AcademicTerm {
  final String name; // "Trimester 1"
  final String academicYear; // "AY2026"
  final List<AcademicWeek> weeks;

  const AcademicTerm({required this.name, required this.academicYear, required this.weeks});

  DateTime get start => weeks.first.start;
  DateTime get end => weeks.last.end;

  /// Teaching weeks plus final assessment, i.e. up to the trimester break.
  List<AcademicWeek> get termWeeks => weeks.where((w) => w.phase != WeekPhase.trimesterBreak).toList();

  Map<String, Object?> toJson() => {
        'name': name,
        'academicYear': academicYear,
        'weeks': [for (final w in weeks) w.toJson()],
      };

  factory AcademicTerm.fromJson(Map<String, Object?> j) => AcademicTerm(
        name: j['name'] as String? ?? '',
        academicYear: j['academicYear'] as String? ?? '',
        weeks: [for (final w in j['weeks'] as List) AcademicWeek.fromJson((w as Map).cast<String, Object?>())],
      );
}

class AcademicYear {
  final String label; // "AY2026"
  final List<AcademicTerm> terms;

  const AcademicYear({required this.label, required this.terms});

  Map<String, Object?> toJson() => {
        'label': label,
        'terms': [for (final t in terms) t.toJson()],
      };

  factory AcademicYear.fromJson(Map<String, Object?> j) => AcademicYear(
        label: j['label'] as String? ?? '',
        terms: [for (final t in j['terms'] as List) AcademicTerm.fromJson((t as Map).cast<String, Object?>())],
      );
}

/// "2026-09-01": a date without a time or zone, as saved.
String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The calendar as saved on the device.
String encodeAcademicYears(List<AcademicYear> years) => jsonEncode([for (final y in years) y.toJson()]);

List<AcademicYear> decodeAcademicYears(String json) => [
      for (final y in jsonDecode(json) as List) AcademicYear.fromJson((y as Map).cast<String, Object?>()),
    ];

/// Where a date sits in the calendar.
class CalendarPosition {
  final AcademicYear year;
  final AcademicTerm term;
  final AcademicWeek week;

  const CalendarPosition(this.year, this.term, this.week);

  /// The next week whose phase differs from this one (e.g. recess, finals),
  /// within this trimester.
  AcademicWeek? get nextChange {
    final i = term.weeks.indexOf(week);
    for (final w in term.weeks.skip(i + 1)) {
      if (w.phase != week.phase) return w;
    }
    return null;
  }
}

class AcademicCalendar {
  final List<AcademicYear> years;

  /// When the page was fetched from SIT's website.
  final DateTime fetchedAt;

  const AcademicCalendar(this.years, this.fetchedAt);

  Iterable<(AcademicYear, AcademicTerm)> get _terms sync* {
    for (final y in years) {
      for (final t in y.terms) {
        yield (y, t);
      }
    }
  }

  /// The year, trimester and week containing [day], if any.
  CalendarPosition? positionOf(DateTime day) {
    for (final (y, t) in _terms) {
      for (final w in t.weeks) {
        if (w.contains(day)) return CalendarPosition(y, t, w);
      }
    }
    return null;
  }

  /// The first week, in date order, that hasn't ended by [day] and matches
  /// [test]. The week containing [day] counts.
  (AcademicTerm, AcademicWeek)? nextWeekWhere(DateTime day, bool Function(AcademicWeek week) test) {
    final d = DateTime(day.year, day.month, day.day);
    (AcademicTerm, AcademicWeek)? best;
    for (final (_, t) in _terms) {
      for (final w in t.weeks) {
        if (w.end.isBefore(d) || !test(w)) continue;
        if (best == null || w.start.isBefore(best.$2.start)) best = (t, w);
      }
    }
    return best;
  }

  /// The Friday that ends Trimester 3's finals in [year] (July/August), from
  /// the calendar; null if the calendar doesn't cover that year.
  DateTime? lastFinalsFriday(int year) {
    DateTime? best;
    for (final (_, t) in _terms) {
      if (!RegExp(r'\b3\b').hasMatch(t.name)) continue;
      for (final w in t.weeks) {
        if (w.phase != WeekPhase.finals) continue;
        final friday = fridayOf(w.start);
        if (friday.year == year && (best == null || friday.isAfter(best))) best = friday;
      }
    }
    return best;
  }

  /// Every Trimester 3 finals-ending Friday the calendar knows.
  List<DateTime> get t3FinalsFridays {
    final years = <int>{for (final (_, t) in _terms) for (final w in t.weeks) w.start.year};
    return [
      for (final y in years.toList()..sort())
        if (lastFinalsFriday(y) case final d?) d,
    ];
  }

  /// The first trimester starting after [day], for gaps between terms.
  (AcademicYear, AcademicTerm)? nextTermAfter(DateTime day) {
    for (final (y, t) in _terms) {
      if (t.start.isAfter(day)) return (y, t);
    }
    return null;
  }
}

/// The Friday of the week starting [weekStart] (the week's Monday or so).
DateTime fridayOf(DateTime weekStart) {
  final d = DateTime(weekStart.year, weekStart.month, weekStart.day);
  return DateTime(d.year, d.month, d.day + (DateTime.friday - d.weekday) % 7);
}

/// Graduation day for a graduation [year]: the Friday that ends Trimester 3
/// finals that year (July/August). From the calendar when it covers that
/// year; otherwise estimated from the latest year it does cover, moved by
/// whole weeks so it stays a Friday; with no calendar at all, the first
/// Friday of August.
({DateTime date, bool estimated}) graduationDay(int year, AcademicCalendar? calendar) {
  final exact = calendar?.lastFinalsFriday(year);
  if (exact != null) return (date: exact, estimated: false);
  final known = calendar?.t3FinalsFridays ?? const <DateTime>[];
  if (known.isNotEmpty) {
    final ref = known.last;
    // Same date that many years on, then the nearest Friday.
    final target = DateTime(year, ref.month, ref.day);
    final offset = (DateTime.friday - target.weekday + 7) % 7;
    final friday = offset <= 3 ? target.add(Duration(days: offset)) : target.subtract(Duration(days: 7 - offset));
    return (date: friday, estimated: true);
  }
  return (date: fridayOf(DateTime(year, 8, 1)), estimated: true);
}
