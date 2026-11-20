import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/results_providers.dart';
import 'package:resit/features/lms/ui/results/assignment_detail_screen.dart';
import 'package:resit/features/lms/ui/results/quiz_detail_screen.dart';
import 'package:resit/features/lms/ui/sections/assignments_screen.dart';
import 'package:resit/features/lms/ui/sections/grades_screen.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts feedback requests instead of asking xSiTe.
class _FakeLms extends LmsService {
  var feedbackCalls = 0;
  _FakeLms() : super(AuthService(SessionClient(MockClient((r) async => http.Response('', 404))), SecureStorage()));

  @override
  Future<AssignmentFeedback?> feedback(Assignment a, {onMfaChallenge}) async {
    feedbackCalls++;
    return const AssignmentFeedback(comments: 'ok');
  }
}

void main() {
  final course = LmsCourse(
    orgUnitId: '213443',
    name: 'INF2004-Embedded Systems Programming [2026/27 T1]',
    code: 'SIT-2610-INF2004',
    semester: '2026/27 Trimester 1',
  );
  const key = (orgUnitId: '213443', id: 501);
  final lab = Assignment(
    orgUnitId: '213443',
    id: 501,
    name: 'Lab 3 report',
    instructions: 'Submit as PDF.',
    dueDate: DateTime(2026, 11, 20, 23, 59),
    outOf: 20,
    gradeItemId: 9001,
    submissions: [DateTime(2026, 11, 18, 21, 5)],
  );
  final grades = CourseGrades([
    GradeEntry(id: 9001, name: 'Lab 3 report', displayed: '17.5 / 20', comment: 'Well done overall'),
    GradeEntry(id: 9002, name: 'Week 9 quiz', displayed: '8 / 10'),
  ]);
  const feedback = AssignmentFeedback(
    score: 17.5,
    comments: 'Clear report.',
    rubrics: [
      RubricResult(name: 'Lab report rubric', overallLevel: 'Distinction', criteria: [
        RubricCriterionResult(criterion: 'Analysis', level: 'Excellent', score: 10, outOf: 10),
      ]),
    ],
    attachments: ['marked-report.pdf'],
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester, Widget home, List<Override> overrides) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: home)));
    await tester.pumpAndSettle();
  }

  testWidgets('an assignment shows its details and released feedback, hidden until grades are shown', (tester) async {
    await pump(tester, AssignmentDetailScreen(course: course, assignment: lab), [
      lmsAssignmentsProvider('213443').overrideWith((ref) async => [lab]),
      lmsGradesProvider('213443').overrideWith((ref) async => grades),
      assignmentFeedbackProvider(key).overrideWith((ref) async => feedback),
    ]);

    expect(find.text('Submit as PDF.'), findsOneWidget);
    expect(find.text('Fri 20 Nov 2026, 23:59'), findsOneWidget);
    expect(find.text('Wed 18 Nov 2026, 21:05'), findsOneWidget);
    expect(find.text('marked-report.pdf'), findsOneWidget);
    // Score, comments, rubric and the grade-book comment are hidden at first.
    expect(find.text('17.5 / 20'), findsNothing);
    expect(find.text('Clear report.', skipOffstage: false), findsOneWidget);
    expect(find.text('Grades hidden · tap to show'), findsNWidgets(3));

    await tester.tap(find.byTooltip('Show grades'));
    await tester.pumpAndSettle();

    expect(find.text('17.5 / 20'), findsNWidgets(2), reason: 'feedback score and grade-book grade');
    expect(find.text('Grades hidden · tap to show'), findsNothing);
    expect(find.text("Instructor's comments"), findsOneWidget);
    expect(find.text('Overall: Distinction'), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('Well done overall'), findsOneWidget);
  });

  testWidgets('without released feedback, the assignment says so', (tester) async {
    await pump(tester, AssignmentDetailScreen(course: course, assignment: lab), [
      lmsAssignmentsProvider('213443').overrideWith((ref) async => [lab]),
      lmsGradesProvider('213443').overrideWith((ref) async => CourseGrades([])),
      assignmentFeedbackProvider(key).overrideWith((ref) async => null),
    ]);
    expect(find.text('No feedback released yet.'), findsOneWidget);
    expect(find.text('Grade'), findsNothing);
  });

  testWidgets('tapping an assignment in the list opens it', (tester) async {
    await pump(tester, AssignmentsScreen(course: course), [
      lmsAssignmentsProvider('213443').overrideWith((ref) async => [lab]),
      lmsGradesProvider('213443').overrideWith((ref) async => grades),
      assignmentFeedbackProvider(key).overrideWith((ref) async => null),
    ]);
    await tester.tap(find.text('Lab 3 report'));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentDetailScreen), findsOneWidget);
    expect(find.text('Your submissions'), findsOneWidget);
  });

  testWidgets('a quiz lists your attempts; scores only once released, hidden by default', (tester) async {
    final quiz = Quiz(orgUnitId: '213443', id: 71, name: 'Week 9 quiz', timeLimit: 30, attemptsAllowed: 2, gradeItemId: 9002);
    await pump(tester, QuizDetailScreen(course: course, quiz: quiz), [
      lmsQuizzesProvider('213443').overrideWith((ref) async => [quiz]),
      lmsGradesProvider('213443').overrideWith((ref) async => grades),
      quizAttemptsProvider((orgUnitId: '213443', id: 71)).overrideWith((ref) async => [
            QuizAttempt(number: 1, completed: DateTime(2026, 11, 3, 14, 5), released: true, score: 8.5),
            QuizAttempt(number: 2, completed: DateTime(2026, 11, 4, 9), released: false),
          ]),
    ]);

    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('2 allowed'), findsOneWidget);
    expect(find.text('Attempt 1'), findsOneWidget);
    expect(find.text('Results not released'), findsOneWidget);
    expect(find.text('8.5'), findsNothing);
    expect(find.text('Open quiz on xSiTe'), findsOneWidget);

    await tester.tap(find.byTooltip('Show grades'));
    await tester.pumpAndSettle();
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('8 / 10'), findsOneWidget);
  });

  testWidgets('quiz attempts closed to students read as not available', (tester) async {
    final quiz = Quiz(orgUnitId: '213443', id: 71, name: 'Week 9 quiz');
    await pump(tester, QuizDetailScreen(course: course, quiz: quiz), [
      lmsQuizzesProvider('213443').overrideWith((ref) async => [quiz]),
      lmsGradesProvider('213443').overrideWith((ref) async => CourseGrades([])),
      quizAttemptsProvider((orgUnitId: '213443', id: 71))
          .overrideWith((ref) async => throw LmsUnavailableException('/attempts/')),
    ]);
    expect(find.text("xSiTe doesn't show your attempts here. Open the quiz on xSiTe."), findsOneWidget);
  });

  testWidgets('grades show the instructor comment under each grade, hidden with grades', (tester) async {
    await pump(tester, GradesScreen(course: course), [
      lmsGradesProvider('213443').overrideWith((ref) async => grades),
    ]);
    expect(find.text('Grades hidden · tap to show'), findsOneWidget);
    await tester.tap(find.byTooltip('Show grades'));
    await tester.pumpAndSettle();
    expect(find.text("Instructor's comment"), findsOneWidget);
    expect(find.text('Well done overall'), findsOneWidget);
  });

  test('feedback is asked again when the course is refreshed or signed out of', () async {
    final lms = _FakeLms();
    var lists = 0;
    final container = ProviderContainer(overrides: [
      lmsServiceProvider.overrideWithValue(lms),
      lmsAssignmentsProvider('213443').overrideWith((ref) async {
        lists++;
        return [lab];
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(assignmentFeedbackProvider(key), (_, __) {});

    expect((await container.read(assignmentFeedbackProvider(key).future))?.comments, 'ok');
    await container.read(assignmentFeedbackProvider(key).future);
    expect(lms.feedbackCalls, 1, reason: 'kept once loaded');

    // Sign-out and the course's refresh invalidate the list.
    container.invalidate(lmsAssignmentsProvider);
    await container.read(assignmentFeedbackProvider(key).future);
    expect(lists, 2);
    expect(lms.feedbackCalls, 2);
  });
}
