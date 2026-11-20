import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/sections/checklists_surveys_screen.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

void main() {
  final course = LmsCourse(
    orgUnitId: '213443',
    name: 'INF2004-Embedded Systems Programming [2026/27 T1]',
    code: 'SIT-2610-INF2004',
    semester: '2026/27 Trimester 1',
  );
  final now = DateTime.now();

  group('checklists and surveys', () {
    Future<void> pump(WidgetTester tester, Future<ChecklistsAndSurveys> Function() load) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [lmsChecklistsSurveysProvider('213443').overrideWith((ref) => load())],
        child: MaterialApp(home: ChecklistsSurveysScreen(course: course)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists checklists by category and surveys with when they are open', (tester) async {
      await pump(
        tester,
        () async => ChecklistsAndSurveys(
          checklists: [
            Checklist(orgUnitId: '213443', id: 5, name: 'Getting started', categories: [
              ChecklistCategory(id: 51, name: 'Read first', items: [
                ChecklistItem(id: 501, name: 'Join the Teams channel'),
                ChecklistItem(id: 502, name: 'Read the module guide', dueDate: now.add(const Duration(days: 3))),
              ]),
            ]),
          ],
          surveys: [
            Survey(
                orgUnitId: '213443',
                id: 31,
                name: 'End of term feedback',
                end: now.add(const Duration(days: 10)),
                isAnonymous: true),
            Survey(orgUnitId: '213443', id: 32, name: 'Week 1 check-in', end: now.subtract(const Duration(days: 60))),
          ],
        ),
      );

      expect(find.text('Getting started'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('Read first'), findsOneWidget);
      expect(find.text('Join the Teams channel'), findsOneWidget);
      expect(find.textContaining('Due '), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Week 1 check-in'), 200);
      expect(find.text('End of term feedback'), findsOneWidget);
      expect(find.text('Anonymous'), findsOneWidget);
      expect(find.text('Take on xSiTe'), findsOneWidget);
      expect(find.textContaining('Closed '), findsOneWidget);
    });

    testWidgets('a course without either tool says so, not an error', (tester) async {
      await pump(tester, () async => throw LmsUnavailableException('checklists and surveys'));
      expect(find.text('Not used in this course'), findsOneWidget);
    });

    testWidgets('a course with neither shows an empty state', (tester) async {
      await pump(tester, () async => ChecklistsAndSurveys(checklists: [], surveys: null));
      expect(find.text('No checklists or surveys'), findsOneWidget);
    });
  });
}
