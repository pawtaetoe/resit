import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/lms/data/lms_service.dart';
import 'package:resit/features/lms/presentation/courses_screen.dart';

ContentTopic _t(int id, String title, {bool unread = true}) => ContentTopic(
    orgUnitId: '213443', id: id, title: title, type: 'File', url: '/content/$title.pdf', unread: unread);

void main() {
  final course = LmsCourse(
    orgUnitId: '213443',
    name: 'INF2004-Embedded Systems Programming [2026/27 T1]',
    code: 'SIT-2610-INF2004',
    semester: '2026/27 Trimester 1',
  );
  final modules = [
    ContentModule(id: 1, title: 'Lecture', topics: [_t(10, 'W9 Sensor Fusion', unread: false), _t(11, 'W10 Optimisations')]),
    ContentModule(id: 2, title: 'Laboratory', topics: [_t(20, 'INF2004 Labs', unread: false)]),
  ];
  ContentItem item(int id, String title, int done) =>
      ContentItem(orgUnitId: '213443', objectId: id, title: title, required: 1, completed: done);
  final progress = CourseProgress([item(10, 'W9 Sensor Fusion', 1), item(11, 'W10 Optimisations', 0), item(20, 'INF2004 Labs', 1)]);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsContentsProvider('213443').overrideWith((ref) async => modules),
        lmsProgressProvider('213443').overrideWith((ref) async => progress),
      ],
      child: MaterialApp(home: CourseScreen(course: course)),
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
}
