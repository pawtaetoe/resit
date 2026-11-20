import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/updates.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/ui/course_card.dart';
import 'package:resit/features/lms/ui/event_tile.dart';
import 'package:resit/features/lms/ui/xsite_calendar_screen.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime day(int n, [int hour = 0, int minute = 0]) => DateTime(today.year, today.month, today.day + n, hour, minute);
  LmsEvent ev(String ou, String code, String title, DateTime start,
          {DateTime? end, bool allDay = false, String location = '', LmsEventKind kind = LmsEventKind.event}) =>
      LmsEvent(
        orgUnitId: ou,
        id: title.hashCode,
        title: title,
        courseName: '$code-Course [2026/27 T1]',
        courseCodeField: 'SIT-2610-$code',
        start: start,
        end: end,
        allDay: allDay,
        location: location,
        kind: kind,
        url: Uri.parse('https://xsite.singaporetech.edu.sg/d2l/le/calendar/$ou'),
      );
  final events = [
    ev('1', 'INF2004', 'Lab 3 report', day(1, 23, 59), kind: LmsEventKind.assignment),
    ev('2', 'CSC2101', 'Sprint review', day(1, 10), end: day(1, 12), location: 'E2-03-12'),
    ev('2', 'CSC2101', 'Demo week', day(3), end: day(6), allDay: true),
  ];
  final to = day(lmsCalendarDays);
  final agendaValue = LmsAgenda(today, to, agenda(events, today, to));
  final inf = LmsCourse(orgUnitId: '1', name: 'INF2004-Embedded Systems [2026/27 T1]', code: 'SIT-2610-INF2004', semester: '');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester, Widget home, {required Future<LmsAgenda> Function() calendar}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => true),
        lmsCalendarProvider.overrideWith((ref) => calendar()),
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the calendar lists events by day: course, time, place', (tester) async {
    await pump(tester, const XsiteCalendarScreen(), calendar: () async => agendaValue);

    expect(find.text(agendaDayLabel(day(1), now)), findsOneWidget);
    expect(find.textContaining('Tomorrow · '), findsOneWidget);
    expect(find.byType(EventTile), findsNWidgets(3));
    // Same day: by time.
    final review = tester.getTopLeft(find.text('Sprint review'));
    final lab = tester.getTopLeft(find.text('Lab 3 report'));
    expect(review.dy, lessThan(lab.dy));
    expect(find.text('CSC2101 · 10:00 – 12:00'), findsOneWidget);
    expect(find.text('E2-03-12'), findsOneWidget);
    expect(find.text('INF2004 · 23:59'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Demo week'), 100);
    expect(find.textContaining('CSC2101 · All day · until '), findsOneWidget);
  });

  testWidgets("one course's calendar shows only its events", (tester) async {
    await pump(tester, XsiteCalendarScreen(course: inf), calendar: () async => agendaValue);

    expect(find.text('Lab 3 report'), findsOneWidget);
    expect(find.text('Sprint review'), findsNothing);
    // The course is in the title, so not on each event.
    expect(find.text('23:59'), findsOneWidget);
    expect(find.text('Open calendar in xSiTe'), findsOneWidget);
  });

  testWidgets('an empty calendar says so', (tester) async {
    await pump(tester, const XsiteCalendarScreen(), calendar: () async => LmsAgenda(today, to, const []));
    expect(find.text('Nothing in the next 4 weeks'), findsOneWidget);
  });

  testWidgets('a calendar xSiTe refuses is "not available", not an error', (tester) async {
    await pump(tester, const XsiteCalendarScreen(),
        calendar: () async => throw LmsUnavailableException('/d2l/api/le/1.75/calendar/events/myEvents/'));
    expect(find.text('Calendar not available'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a course card shows what is new, read out in full', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsProgressProvider('1').overrideWith((ref) async => CourseProgress(const [])),
        lmsUpdatesProvider.overrideWith(
            (ref) async => {'1': const CourseUpdates(unreadDiscussions: 2, unreadFeedback: 1)}),
      ],
      child: MaterialApp(home: Scaffold(body: CourseCard(course: inf))),
    ));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('2 unread discussions, 1 new assignment feedback')), findsOneWidget);
    expect(find.text('3 new'), findsOneWidget);
    handle.dispose();
  });
}
