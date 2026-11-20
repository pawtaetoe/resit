import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/discussions_providers.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/updates.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/course_screen.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/course_content_screen.dart';
import 'package:resit/features/lms/ui/term_announcements.dart';

ContentTopic _t(int id, String title, {bool unread = true}) =>
    ContentTopic(orgUnitId: '213443', id: id, title: title, type: 'File', url: '/content/$title.pdf', unread: unread);

void main() {
  final course = LmsCourse(
    orgUnitId: '213443',
    name: 'INF2004-Embedded Systems Programming [2026/27 T1]',
    code: 'SIT-2610-INF2004',
    semester: '2026/27 Trimester 1',
  );
  final modules = [
    ContentModule(
        id: 1, title: 'Lecture', topics: [_t(10, 'W9 Sensor Fusion', unread: false), _t(11, 'W10 Optimisations')]),
    ContentModule(id: 2, title: 'Laboratory', topics: [_t(20, 'INF2004 Labs', unread: false)]),
  ];
  ContentItem item(int id, String title, int done) =>
      ContentItem(orgUnitId: '213443', objectId: id, title: title, required: 1, completed: done);
  final progress =
      CourseProgress([item(10, 'W9 Sensor Fusion', 1), item(11, 'W10 Optimisations', 0), item(20, 'INF2004 Labs', 1)]);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsContentsProvider('213443').overrideWith((ref) async => modules),
        lmsProgressProvider('213443').overrideWith((ref) async => progress),
      ],
      child: MaterialApp(home: CourseContentScreen(course: course)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a course shows progress, and items already read stay listed', (tester) async {
    await pump(tester);

    expect(find.text('67% done'), findsOneWidget);
    expect(find.text('2 of 3 items · 2026/27 T1'), findsOneWidget);
    // Read and unread items in the same folder are both there, read ones ticked.
    expect(find.text('W10 Optimisations'), findsOneWidget);
    expect(find.text('W9 Sensor Fusion'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // A finished folder is still listed (closed, with its count).
    expect(find.text('Laboratory'), findsOneWidget);
    expect(find.text('1 of 1 done'), findsOneWidget);
    await tester.tap(find.text('Laboratory'));
    await tester.pumpAndSettle();
    expect(find.text('INF2004 Labs'), findsOneWidget);
  });

  testWidgets('the course overview shows what is due and every section', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 2));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsProgressProvider('213443').overrideWith((ref) async => progress),
        lmsAnnouncementsProvider('213443').overrideWith(
            (ref) async => [Announcement(id: '1', title: 'Lab moved', body: 'x', date: DateTime(2026, 11, 2))]),
        lmsAssignmentsProvider('213443')
            .overrideWith((ref) async => [Assignment(orgUnitId: '213443', id: 1, name: 'Lab 3 report', dueDate: soon)]),
        lmsQuizzesProvider('213443').overrideWith((ref) async => <Quiz>[]),
        lmsGradesProvider('213443').overrideWith((ref) async => CourseGrades([])),
        lmsGroupsProvider('213443').overrideWith((ref) async => [MyGroup(category: 'Project', name: 'P2')]),
        lmsDiscussionsProvider('213443').overrideWith((ref) async => <DiscussionForum>[]),
        lmsCourseUpdatesProvider('213443')
            .overrideWith((ref) async => const CourseUpdates(unreadFeedback: 2, unattemptedQuizzes: 1)),
        lmsCalendarProvider.overrideWith((ref) async => LmsAgenda(DateTime.now(), soon, [
              AgendaDay(soon, [
                LmsEvent(orgUnitId: '213443', id: 1, title: 'Lab test', start: soon, url: course.homeUrl),
              ]),
            ])),
        lmsChecklistsSurveysProvider('213443').overrideWith((ref) async =>
            ChecklistsAndSurveys(checklists: [Checklist(orgUnitId: '213443', id: 5, name: 'Start')], surveys: [])),
      ],
      child: MaterialApp(home: CourseScreen(course: course)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Lab 3 report'), findsOneWidget);
    expect(find.byType(DueTile), findsOneWidget);
    await tester.scrollUntilVisible(find.text('2 of 3 items done'), 100);
    // Every section, top to bottom, with what's new beside the sections it's
    // about, and what's coming up.
    for (final s in [
      'Content',
      'Announcements',
      'Assignments',
      '2 new feedback',
      'Quizzes',
      '1 to attempt',
      'Grades',
      'Groups',
      'P2',
      'Discussions',
      'Checklists and surveys',
      '1 checklist',
      'Calendar',
    ]) {
      await tester.scrollUntilVisible(find.text(s), 100);
      expect(find.text(s), findsOneWidget, reason: s);
    }
    final next = find.textContaining(RegExp(r'^Next: Lab test, .* · 1 event in 4 weeks$'));
    await tester.scrollUntilVisible(next, 100);
    expect(next, findsOneWidget);
  });

  testWidgets('latest announcements across this term: newest 5, the rest under "more"', (tester) async {
    LmsCourse c(String id, String code) =>
        LmsCourse(orgUnitId: id, name: '$code-Course [2026/27 T1]', code: 'SIT-$code', semester: '2026/27 Trimester 1');
    final a = c('1', 'INF2004'), b = c('2', 'CSC2101');
    Announcement n(String t, int day) =>
        Announcement(id: t, title: t, body: 'Body of $t', date: DateTime(2026, 11, day));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsAnnouncementsProvider('1').overrideWith((ref) async => [n('A1', 10), n('A2', 8), n('A3', 2)]),
        lmsAnnouncementsProvider('2').overrideWith((ref) async => [n('B1', 12), n('B2', 9), n('B3', 5), n('B4', 1)]),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        TermAnnouncements(courses: [a, b])
      ]))),
    ));
    await tester.pumpAndSettle();

    for (final t in ['B1', 'A1', 'B2', 'A2', 'B3']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('A3'), findsNothing);
    expect(find.text('2 more announcements'), findsOneWidget);
    await tester.tap(find.text('2 more announcements'));
    await tester.pumpAndSettle();
    expect(find.text('A3'), findsOneWidget);
    expect(find.text('B4'), findsOneWidget);
  });
}
