import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/lms/discussions_providers.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/ui/sections/discussions_screen.dart';
import 'package:resit/features/lms/ui/sections/topic_screen.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

void main() {
  final course = LmsCourse(
    orgUnitId: '213443',
    name: 'INF2004-Embedded Systems Programming [2026/27 T1]',
    code: 'SIT-2610-INF2004',
    semester: '2026/27 Trimester 1',
  );
  const labs = DiscussionTopic(
      orgUnitId: '213443', forumId: 1, id: 10, name: 'Lab questions', description: 'Ask about the labs here.');
  final later = DiscussionTopic(
      orgUnitId: '213443',
      forumId: 1,
      id: 11,
      name: 'Exam revision',
      access: TopicAccess.notYetOpen,
      accessDate: DateTime(2026, 12, 1, 9));
  final forums = [
    DiscussionForum(id: 1, name: 'Course Q&A', topics: [labs, later]),
  ];
  DiscussionPost post(int id, int thread, int? parent, String subject, DateTime date, {bool read = true}) =>
      DiscussionPost(
          id: id,
          threadId: thread,
          parentId: parent,
          subject: subject,
          author: 'Alex Tan',
          date: date,
          body: 'Text of $subject',
          isRead: read);
  final posts = TopicPosts.from([
    post(1, 1, null, 'Lab 3 timer', DateTime(2026, 11, 10, 11)),
    post(2, 1, 1, 'Re: Lab 3 timer', DateTime(2026, 11, 10, 13)),
    post(3, 1, 2, 'Still stuck', DateTime(2026, 11, 11, 9), read: false),
    post(4, 4, null, 'Week 10 question', DateTime(2026, 11, 15, 10)),
    for (var i = 0; i < 25; i++) post(100 + i, 100 + i, null, 'Old thread $i', DateTime(2026, 9, 1 + i)),
  ]);

  Future<void> pump(WidgetTester tester, Widget screen, {Future<List<DiscussionForum>> Function()? load}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsDiscussionsProvider('213443').overrideWith((ref) => load?.call() ?? Future.value(forums)),
        lmsTopicPostsProvider(labs.key).overrideWith((ref) async => posts),
      ],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('forums list their topics with counts; a topic opens its threads', (tester) async {
    await pump(tester, DiscussionsScreen(course: course));

    expect(find.text('Course Q&A'), findsOneWidget);
    expect(find.text('Lab questions'), findsOneWidget);
    expect(find.text('29 posts · 1 unread · last 15 Nov'), findsOneWidget);
    // A topic that isn't open yet says when it opens and doesn't open.
    expect(find.text('Opens 1 Dec, 09:00'), findsOneWidget);
    await tester.tap(find.text('Exam revision'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicScreen), findsNothing);

    await tester.tap(find.text('Lab questions'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicScreen), findsOneWidget);
    // Newest thread first, replies under the first post; an echoing
    // "Re:" subject is left out, a real one kept.
    expect(find.text('Ask about the labs here.'), findsOneWidget);
    expect(find.text('Reply on xSiTe'), findsOneWidget);
    final week10 = tester.getTopLeft(find.text('Week 10 question'));
    final lab3 = tester.getTopLeft(find.text('Lab 3 timer'));
    expect(week10.dy, lessThan(lab3.dy));
    expect(find.text('Re: Lab 3 timer'), findsNothing);
    expect(find.text('Text of Re: Lab 3 timer'), findsOneWidget);
    final reply = tester.getTopLeft(find.text('Text of Re: Lab 3 timer'));
    final deeper = tester.getTopLeft(find.text('Still stuck'));
    expect(reply.dx, greaterThan(lab3.dx));
    expect(deeper.dx, greaterThan(reply.dx));
    expect(find.text('New'), findsOneWidget);

    // 27 threads: 20 shown, the rest behind "more".
    await tester.scrollUntilVisible(find.textContaining('Show more threads'), 300);
    expect(find.text('Show more threads (7 left)'), findsOneWidget);
    expect(find.text('Old thread 0'), findsNothing);
    await tester.tap(find.textContaining('Show more threads'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Old thread 0'), 300);
    expect(find.text('Old thread 0'), findsOneWidget);
    expect(find.textContaining('Show more threads'), findsNothing);
  });

  testWidgets('discussions turned off for the course read as not used, not an error', (tester) async {
    await pump(tester, DiscussionsScreen(course: course),
        load: () async => throw LmsUnavailableException('/discussions/forums/'));
    expect(find.text('Not used in this course'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
