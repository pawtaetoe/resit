import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/meeting_providers.dart';
import 'package:resit/features/lms/ui/class_meeting_button.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

LmsCourse _course(String id, String code, {DateTime? start, bool active = true}) => LmsCourse(
      orgUnitId: id,
      name: '$code-Course [2026/27 T1]',
      code: 'SIT-2610-$code',
      semester: '2026/27 Trimester 1',
      start: start,
      isActive: active,
    );

final _zoom = MeetingLink(
  url: Uri.parse('https://sit-edu.zoom.us/j/91234567890'),
  service: MeetingService.zoom,
  meetingId: '912 3456 7890',
  passcode: 'inf2004!',
);

ClassSession _class(String code, String location) => ClassSession(
      date: DateTime(2026, 11, 20),
      courseCode: code,
      section: 'L1',
      component: 'Lecture',
      startMin: 9 * 60,
      endMin: 11 * 60,
      location: location,
      coinciding: false,
    );

/// Counts course-list reads; never goes online.
class _FakeLms extends LmsService {
  final List<LmsCourse> list;
  var reads = 0;
  _FakeLms(this.list) : super(AuthService(SessionClient(), SecureStorage()));

  @override
  Future<List<LmsCourse>> courses({void Function(MfaChallenge)? onMfaChallenge, bool force = false}) async {
    reads++;
    return list;
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('an online class on Home', () {
    Future<void> pump(WidgetTester tester, ClassSession c, List<Override> overrides) async {
      // A fresh scope each time.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => true), ...overrides],
        child: MaterialApp(
          home: Scaffold(
            body: ListTile(
                title: const Text('class'),
                trailing: ClassMeetingButton(session: c, fallback: const Icon(Icons.chevron_right))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows Join from the module\'s newest announcement with a link', (tester) async {
      final lms = _FakeLms([
        _course('900', 'CSC2101'),
        _course('300', 'INF2004', start: DateTime(2026, 8, 24)),
        _course('100', 'INF2004', start: DateTime(2025, 8, 24)),
      ]);
      final read = <String>[];
      await pump(tester, _class('INF 2004', 'Online'), [
        lmsServiceProvider.overrideWith((ref) => lms),
        lmsAnnouncementsProvider.overrideWith((ref, id) async {
          read.add(id);
          final older = MeetingLink(url: Uri.parse('https://zoom.us/j/1111111111'), service: MeetingService.zoom);
          return [
            Announcement(id: 'b', title: 'Quiz', body: '', date: DateTime(2026, 11, 18)),
            Announcement(id: 'a', title: 'Zoom', body: '', date: DateTime(2026, 11, 10), meetings: [_zoom]),
            Announcement(id: 'c', title: 'Old zoom', body: '', date: DateTime(2026, 9, 1), meetings: [older]),
          ];
        }),
      ]);

      expect(find.text('Join'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      // Just this module's announcements, from this term's course.
      expect(read, ['300']);

      // A long press shows the ID and passcode to copy.
      await tester.longPress(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.text('INF 2004 Lecture on Zoom'), findsOneWidget);
      expect(find.text('ID 912 3456 7890'), findsOneWidget);
    });

    testWidgets('a class in a room, or a module with no link, keeps the chevron and reads nothing', (tester) async {
      final lms = _FakeLms([_course('300', 'INF2004')]);
      var reads = 0;
      final overrides = [
        lmsServiceProvider.overrideWith((ref) => lms),
        lmsAnnouncementsProvider.overrideWith((ref, id) async {
          reads++;
          return [Announcement(id: 'a', title: 'Hi', body: '')];
        }),
      ];
      await pump(tester, _class('INF 2004', 'E2-03-01'), overrides);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(lms.reads, 0);
      expect(reads, 0);

      await pump(tester, _class('INF 2004', 'Online'), overrides);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.text('Join'), findsNothing);
    });

    testWidgets('a module xSiTe doesn\'t list, or with announcements closed, keeps the chevron', (tester) async {
      await pump(tester, _class('CSC 3104', 'Online'), [
        lmsServiceProvider.overrideWith((ref) => _FakeLms([_course('300', 'INF2004')])),
      ]);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await pump(tester, _class('INF 2004', 'Online'), [
        lmsServiceProvider.overrideWith((ref) => _FakeLms([_course('300', 'INF2004')])),
        lmsAnnouncementsProvider.overrideWith((ref, id) async => throw LmsUnavailableException('/news/')),
      ]);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('signed out: nothing is read', (tester) async {
      final lms = _FakeLms([_course('300', 'INF2004')]);
      await tester.pumpWidget(ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => false), lmsServiceProvider.overrideWith((ref) => lms)],
        child: MaterialApp(
          home: Scaffold(
              body:
                  ClassMeetingButton(session: _class('INF 2004', 'Online'), fallback: const Icon(Icons.chevron_right))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(lms.reads, 0);
    });
  });

  test('a module finds its xSiTe course: newest term, open ones first', () {
    final courses = [
      _course('3', 'INF2004', active: false),
      _course('2', 'INF2004'),
      _course('1', 'CSC2101'),
    ];
    expect(courseForModule(courses, 'INF 2004')?.orgUnitId, '2');
    expect(courseForModule(courses, 'inf2004')?.orgUnitId, '2');
    expect(courseForModule([_course('3', 'INF2004', active: false)], 'INF 2004')?.orgUnitId, '3');
    expect(courseForModule(courses, 'CSC 3104'), isNull);
  });
}
