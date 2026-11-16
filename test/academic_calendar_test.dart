import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:resit/sites/sit_website/academic_calendar_service.dart';

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

  test('the parsed calendar round-trips through its saved JSON', () {
    final back = decodeAcademicYears(encodeAcademicYears(years));
    expect(back.map((y) => y.label), years.map((y) => y.label));
    final t1 = back[1].terms[0];
    expect(t1.weeks, hasLength(18));
    expect(t1.weeks.first.start, DateTime(2026, 8, 31));
    expect(t1.weeks[17].end, DateTime(2027, 1, 3));
    expect(t1.weeks[6].phase, WeekPhase.recess);
    expect(t1.weeks[9].holidayWeekendOrMonday, isTrue);
    expect(t1.weeks[16].holidayWeekday, isTrue);
    expect(AcademicCalendar(back, DateTime(2026)).positionOf(DateTime(2026, 11, 2))?.week.number, 10);
  });

  test('a calendar saved as HTML by an older version still loads offline', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'academic_calendar_html': html, 'academic_calendar_fetched': 1});
    final offline = MockClient((r) async => throw Exception('offline'));
    final loaded = await AcademicCalendarService(offline).load();
    expect(loaded.years, hasLength(3));

    // Fetched afresh, it is saved parsed, and the HTML copy goes.
    final online = MockClient((r) async => http.Response(html, 200));
    await AcademicCalendarService(online).load(force: true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('academic_calendar_html'), isNull);
    expect(decodeAcademicYears(prefs.getString('academic_calendar_json')!), hasLength(3));
  });

  test('finds the next week matching a condition', () {
    final today = DateTime(2026, 11, 2);
    final finals = calendar.nextWeekWhere(today, (w) => w.phase == WeekPhase.finals)!;
    expect(finals.$2.start, DateTime(2026, 11, 30));
    final holiday = calendar.nextWeekWhere(today, (w) => w.hasHoliday)!;
    expect(holiday.$2.start, DateTime(2026, 11, 2), reason: 'this week (2 Nov - 8 Nov^) counts');
    final brk = calendar.nextWeekWhere(today, (w) => w.phase == WeekPhase.trimesterBreak)!;
    expect(brk.$2.start, DateTime(2026, 12, 7));
  });
}
