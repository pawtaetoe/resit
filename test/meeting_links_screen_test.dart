import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/ui/sections/announcements_screen.dart';
import 'package:resit/features/lms/ui/term_announcements.dart';

LmsCourse _course(String id, String code) => LmsCourse(
      orgUnitId: id,
      name: '$code-Course [2026/27 T1]',
      code: 'SIT-2610-$code',
      semester: '2026/27 Trimester 1',
    );

final _zoom = MeetingLink(
  url: Uri.parse('https://sit-edu.zoom.us/j/91234567890'),
  service: MeetingService.zoom,
  meetingId: '912 3456 7890',
  passcode: 'inf2004!',
);

void main() {
  testWidgets('a course announcement with a Zoom link offers Join, and copies its ID and passcode', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    final course = _course('213443', 'INF2004');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsAnnouncementsProvider('213443').overrideWith((ref) async => [
              Announcement(id: '1', title: 'Week 10 lecture online', body: 'Join here.', meetings: [_zoom]),
              Announcement(id: '2', title: 'Lab moved', body: 'E2-05-14'),
            ]),
      ],
      child: MaterialApp(home: AnnouncementsScreen(course: course)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Join Zoom'), findsOneWidget);
    expect(find.text('ID 912 3456 7890'), findsOneWidget);

    await tester.tap(find.text('ID 912 3456 7890'));
    await tester.pumpAndSettle();
    expect(copied, '91234567890');
    expect(find.text('Meeting ID copied'), findsOneWidget);

    await tester.tap(find.text('Passcode'));
    await tester.pumpAndSettle();
    expect(copied, 'inf2004!');
    expect(find.text('Passcode copied'), findsOneWidget);
  });

  testWidgets('the term announcements list offers Join on a tile with a link', (tester) async {
    final teams =
        MeetingLink(url: Uri.parse('https://teams.microsoft.com/l/meetup-join/abc'), service: MeetingService.teams);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lmsAnnouncementsProvider('1').overrideWith((ref) async => [
              Announcement(
                  id: '1', title: 'Consultation', body: 'On Teams', date: DateTime(2026, 11, 3), meetings: [teams]),
              Announcement(id: '2', title: 'No link', body: 'x', date: DateTime(2026, 11, 2)),
            ]),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        TermAnnouncements(courses: [_course('1', 'CSC2101')])
      ]))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Join Teams'), findsOneWidget);
  });
}
