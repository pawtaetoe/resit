import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/calendar/data/academic_calendar.dart';

void main() {
  final html = File('test/fixtures/sit_academic_calendar.html').readAsStringSync();
  final years = parseAcademicCalendar(html);
  final calendar = AcademicCalendar(years, DateTime(2026, 11, 2));

  test('reads every academic year and trimester', () {
    expect(years.map((y) => y.label), ['AY2025', 'AY2026', 'AY2027']);
    for (final y in years) {
      expect(y.terms.map((t) => t.name), ['Trimester 1', 'Trimester 2', 'Trimester 3']);
    }
    final t1 = years[1].terms[0];
    expect(t1.weeks, hasLength(18), reason: 'Trimester 1 has a week 18 into the new year');
    expect(years[1].terms[1].weeks, hasLength(17));
  });

  test('reads dates, phases and holiday marks', () {
    final t1 = years[1].terms[0]; // AY2026 Trimester 1, starting 31 Aug 2026
    expect(t1.weeks.first.start, DateTime(2026, 8, 31));
    expect(t1.weeks.first.end, DateTime(2026, 9, 6));
    expect(t1.weeks[6].phase, WeekPhase.recess);
    expect(t1.weeks[7].phase, WeekPhase.study, reason: 'the Schedule cell spans rows');
    expect(t1.weeks[13].phase, WeekPhase.finals);
    expect(t1.weeks[14].phase, WeekPhase.trimesterBreak);
    expect(t1.weeks[17].start, DateTime(2026, 12, 28));
    expect(t1.weeks[17].end, DateTime(2027, 1, 3), reason: 'rolls into the next year');
    expect(t1.weeks[9].holidayWeekendOrMonday, isTrue, reason: '2 Nov - 8 Nov^');
    expect(t1.weeks[16].holidayWeekday, isTrue, reason: '21 Dec - 27 Dec*');

    final t3 = years[0].terms[2]; // "25 May - 31 May^*"
    expect(t3.weeks[3].holidayWeekendOrMonday && t3.weeks[3].holidayWeekday, isTrue);
    expect(years[0].terms[0].weeks[7].start, DateTime(2025, 10, 20), reason: '"20^ Oct" with the mark mid-date');
  });

  test('finds where a date sits', () {
    final now = calendar.positionOf(DateTime(2026, 11, 2))!;
    expect(now.year.label, 'AY2026');
    expect(now.term.name, 'Trimester 1');
    expect(now.week.number, 10);
    expect(now.week.phase, WeekPhase.study);
    expect(now.nextChange?.phase, WeekPhase.finals);
    expect(now.nextChange?.start, DateTime(2026, 11, 30));

    expect(calendar.positionOf(DateTime(2026, 10, 14))?.week.phase, WeekPhase.recess);
    expect(calendar.positionOf(DateTime(2030, 1, 1)), isNull);
    expect(calendar.nextTermAfter(DateTime(2026, 11, 2))?.$2.start, DateTime(2027, 1, 4));
  });
}
