import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:resit/sites/sit_website/academic_calendar_parsers.dart';

void main() {
  final calendar = AcademicCalendar(
      parseAcademicCalendar(File('test/fixtures/sit_academic_calendar.html').readAsStringSync()), DateTime(2026));

  test('graduation day is the Friday that ends Trimester 3 finals that year', () {
    final known = calendar.t3FinalsFridays;
    expect(known, isNotEmpty);
    for (final d in known) {
      expect(d.weekday, DateTime.friday);
      expect(d.month, anyOf(7, 8));
    }
    final year = known.last.year;
    final g = graduationDay(year, calendar);
    expect(g.estimated, isFalse);
    expect(g.date, known.last);
    // It's a finals week in a Trimester 3.
    final pos = calendar.positionOf(g.date)!;
    expect(pos.term.name, contains('3'));
    expect(pos.week.phase, WeekPhase.finals);
  });

  test('a year past the calendar is estimated from the last known year, still on a Friday', () {
    final last = calendar.t3FinalsFridays.last;
    final g = graduationDay(last.year + 2, calendar);
    expect(g.estimated, isTrue);
    expect(g.date.weekday, DateTime.friday);
    expect(g.date.year, last.year + 2);
    expect(g.date.difference(DateTime(last.year + 2, last.month, last.day)).inDays.abs(), lessThanOrEqualTo(3));
  });

  test('without a calendar: the first Friday of August', () {
    final g = graduationDay(2028, null);
    expect(g.estimated, isTrue);
    expect(g.date, DateTime(2028, 8, 4));
  });
}
