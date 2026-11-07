import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// What a week of the trimester is for, from the calendar's Schedule column.
enum WeekPhase { study, recess, finals, trimesterBreak, other }

WeekPhase _phaseOf(String text) {
  final t = text.toLowerCase();
  if (t.contains('recess')) return WeekPhase.recess;
  if (t.contains('final') || t.contains('assessment') || t.contains('exam')) return WeekPhase.finals;
  if (t.contains('break')) return WeekPhase.trimesterBreak;
  if (t.contains('study')) return WeekPhase.study;
  return WeekPhase.other;
}

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

  /// The first trimester starting after [day], for gaps between terms.
  (AcademicYear, AcademicTerm)? nextTermAfter(DateTime day) {
    for (final (y, t) in _terms) {
      if (t.start.isAfter(day)) return (y, t);
    }
    return null;
  }
}

/// Reads SIT's "Academic Calendar for SIT and Joint Programmes" page: one
/// accordion section per academic year, each with a table of Week, Schedule
/// and a column per trimester ("1 Sep - 7 Sep", with ^ and * marking public
/// holidays). The Schedule cell spans several rows; the row of years per
/// trimester sits in the table head or the first body row.
List<AcademicYear> parseAcademicCalendar(String html) {
  final doc = parser.parse(html);
  final years = <AcademicYear>[];

  for (final table in doc.querySelectorAll('table')) {
    final rows = table.querySelectorAll('tr');
    final headers = <List<String>>[];
    final body = <List<String>>[];
    for (final tr in rows) {
      final cells = tr.children.where((c) => c.localName == 'td' || c.localName == 'th').toList();
      final texts = cells.map(_text).toList();
      if (cells.every((c) => c.localName == 'th')) {
        headers.add(texts);
      } else {
        body.add(texts);
      }
    }

    // Trimester names, and each trimester's calendar year.
    final nameRow = headers.firstWhere((r) => r.any((c) => c.toLowerCase().contains('trimester')), orElse: () => []);
    final yearRow =
        headers.firstWhere((r) => r.isNotEmpty && r.first.toLowerCase().startsWith('week'), orElse: () => []);
    if (nameRow.isEmpty || yearRow.isEmpty) continue;
    final termNames = nameRow.where((c) => c.toLowerCase().contains('trimester')).toList();
    final termYears = yearRow.skip(yearRow.length - termNames.length).map((c) => int.tryParse(c)).toList();
    if (termYears.any((y) => y == null)) continue;

    final label = _yearLabel(table) ?? 'AY${termYears.first}';
    final weeks = List.generate(termNames.length, (_) => <AcademicWeek>[]);
    var schedule = '';

    for (final row in body) {
      // A row with every column carries its own Schedule cell; a shorter one
      // continues the Schedule cell spanning from above.
      final hasSchedule = row.length >= termNames.length + 2;
      final number = int.tryParse(row.first);
      if (number == null) continue;
      if (hasSchedule) schedule = row[1];
      final dates = row.skip(row.length - termNames.length).toList();

      for (var i = 0; i < termNames.length; i++) {
        final prev = weeks[i].isEmpty ? null : weeks[i].last.start;
        final week = _parseWeek(number, schedule, dates[i], termYears[i]!, prev);
        if (week != null) weeks[i].add(week);
      }
    }

    years.add(AcademicYear(
      label: label,
      terms: [
        for (var i = 0; i < termNames.length; i++)
          if (weeks[i].isNotEmpty) AcademicTerm(name: termNames[i], academicYear: label, weeks: weeks[i]),
      ],
    ));
  }
  return years;
}

/// "Academic Calendar AY2026" from the accordion section holding [table].
String? _yearLabel(dom.Element table) {
  for (var p = table.parent; p != null; p = p.parent) {
    final title = p.querySelector('.accordion__li-title-content');
    if (title != null) {
      final m = RegExp(r'AY\s*\d{4}', caseSensitive: false).firstMatch(_text(title));
      return m?.group(0)?.replaceAll(' ', '').toUpperCase();
    }
  }
  return null;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// "20^ Oct - 26 Oct", "25 May - 31 May^*", "29 Dec - 4 Jan*". [year] is the
/// trimester's calendar year; weeks that run past New Year roll over.
AcademicWeek? _parseWeek(int number, String schedule, String text, int year, DateTime? previousStart) {
  final m = RegExp(
          r'(\d{1,2})\s*([\^*]*)\s*([A-Za-z]{3})[a-z]*\s*([\^*]*)\s*[-–]\s*(\d{1,2})\s*([\^*]*)\s*([A-Za-z]{3})[a-z]*\s*([\^*]*)')
      .firstMatch(text);
  if (m == null) return null;
  final startMonth = _months[m.group(3)!.toLowerCase()];
  final endMonth = _months[m.group(7)!.toLowerCase()];
  if (startMonth == null || endMonth == null) return null;

  var start = DateTime(year, startMonth, int.parse(m.group(1)!));
  if (previousStart != null && start.isBefore(previousStart)) start = DateTime(year + 1, startMonth, start.day);
  var end = DateTime(start.year, endMonth, int.parse(m.group(5)!));
  if (end.isBefore(start)) end = DateTime(start.year + 1, endMonth, end.day);

  final marks = [m.group(2), m.group(4), m.group(6), m.group(8)].join();
  return AcademicWeek(
    number: number,
    phase: _phaseOf(schedule),
    schedule: schedule,
    start: start,
    end: end,
    holidayWeekendOrMonday: marks.contains('^'),
    holidayWeekday: marks.contains('*'),
  );
}

String _text(dom.Element el) => el.text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Fetches SIT's public academic calendar page and keeps the last good copy,
/// so the calendar works offline and loads instantly.
class AcademicCalendarService {
  static final pageUrl =
      Uri.parse('https://www.singaporetech.edu.sg/admissions/undergraduate/academic-calendar-sit-and-joint-programmes');
  /// Older versions saved the page's HTML; it's still read if no parsed
  /// copy has been saved yet.
  static const _keyHtml = 'academic_calendar_html';
  static const _keyJson = 'academic_calendar_json';
  static const _keyFetched = 'academic_calendar_fetched';

  /// The calendar rarely changes; a copy this fresh isn't re-fetched.
  static const maxAge = Duration(days: 1);

  final http.Client _client;

  AcademicCalendarService([http.Client? client]) : _client = client ?? http.Client();

  /// The calendar: the saved copy if it's recent, otherwise fetched from
  /// SIT's website (falling back to the saved copy when offline). [force]
  /// always tries the website first.
  Future<AcademicCalendar> load({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedAt = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_keyFetched) ?? 0);
    final saved = _saved(prefs, savedAt);

    if (!force && saved != null && saved.years.isNotEmpty && DateTime.now().difference(savedAt) < maxAge) {
      return saved;
    }

    try {
      final response = await _client.get(pageUrl).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('SIT website returned ${response.statusCode}.');
      final html = response.body;
      final years = await compute(parseAcademicCalendar, html, debugLabel: 'academic calendar');
      if (years.isEmpty) throw Exception("Couldn't find the calendar on SIT's website.");
      final now = DateTime.now();
      await prefs.setString(_keyJson, encodeAcademicYears(years));
      await prefs.setInt(_keyFetched, now.millisecondsSinceEpoch);
      await prefs.remove(_keyHtml);
      return AcademicCalendar(years, now);
    } catch (e) {
      if (saved != null && saved.years.isNotEmpty) return saved;
      rethrow;
    }
  }

  /// The saved calendar: the parsed copy, or an older version's saved HTML.
  AcademicCalendar? _saved(SharedPreferences prefs, DateTime savedAt) {
    final json = prefs.getString(_keyJson);
    if (json != null) {
      try {
        return AcademicCalendar(decodeAcademicYears(json), savedAt);
      } catch (_) {
        // Unreadable: fall back to the HTML, if any, or fetch afresh.
      }
    }
    final html = prefs.getString(_keyHtml);
    return html == null ? null : AcademicCalendar(parseAcademicCalendar(html), savedAt);
  }
}
