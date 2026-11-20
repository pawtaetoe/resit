import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/calendar_parsers.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Calendar.EventDataInfo block, as documented.
Map<String, Object?> _event(
  int id,
  String title, {
  String? start,
  String? end,
  bool allDay = false,
  String? startDay,
  String? endDay,
  String location = '',
  Map<String, Object?>? entity,
  String? viewUrl,
  Map<String, Object?>? recurrence,
}) =>
    {
      'CalendarEventId': id,
      'OrgUnitId': 213443,
      'Title': title,
      'Description': '<p>Bring your <b>Pico</b></p>',
      'StartDateTime': start,
      'EndDateTime': end,
      'IsAllDayEvent': allDay,
      'StartDay': startDay,
      'EndDay': endDay,
      'GroupId': null,
      'IsRecurring': recurrence != null,
      'RecurrenceInfo': recurrence,
      'LocationId': null,
      'LocationName': location,
      'OrgUnitName': 'INF2004-Embedded Systems Programming [2026/27 T1]',
      'OrgUnitCode': 'SIT-2610-INF2004',
      'IsAssociatedWithEntity': entity != null,
      'AssociatedEntity': entity,
      'HasVisibilityRestrictions': false,
      'VisibilityRestrictions': {'Type': 1, 'Range': null, 'HiddenRangeUnitType': null, 'StartDate': null, 'EndDate': null},
      'CalendarEventViewUrl': viewUrl,
      'Presenters': [],
    };

final _events = jsonEncode({
  'Objects': [
    _event(5001, 'Lab 3 report due',
        start: '2026-11-21T15:59:00.000Z',
        end: '2026-11-21T15:59:00.000Z',
        entity: {
          'AssociatedEntityType': 'D2L.LE.Dropbox.Dropbox',
          'AssociatedEntityId': 88123,
          'Link': '/d2l/lms/dropbox/user/folder_submit_files.d2l?db=88123&ou=213443',
        },
        viewUrl: 'https://xsite.singaporetech.edu.sg/d2l/le/calendar/213443/event/5001/detailsview'),
    _event(5002, 'Project demo day',
        allDay: true, startDay: '2026-11-24T00:00:00.000', endDay: '2026-11-26T00:00:00.000', location: 'SIT@Punggol E2-03'),
    _event(5003, 'Guest talk',
        start: '2026-11-25T02:00:00.000Z',
        end: '2026-11-25T04:00:00.000Z',
        // A link that leaves xSiTe is ignored: the event opens on xSiTe.
        viewUrl: 'https://evil.example.com/phish'),
    _event(5004, 'No date at all'),
    'not an event',
  ],
  'Next': null,
});

void main() {
  test('reads events: times in local time, all-day days, links kept on xSiTe', () {
    final page = parseMyEvents(_events);
    expect(page.next, isNull);
    expect(page.events.map((e) => e.title), ['Lab 3 report due', 'Project demo day', 'Guest talk']);

    final due = page.events[0];
    expect(due.start, DateTime.utc(2026, 11, 21, 15, 59).toLocal());
    expect(due.isInstant, isTrue);
    expect(due.kind, LmsEventKind.assignment);
    expect(due.courseCode, 'INF2004');
    expect(due.description, 'Bring your Pico');
    expect(due.url.toString(),
        'https://xsite.singaporetech.edu.sg/d2l/lms/dropbox/user/folder_submit_files.d2l?db=88123&ou=213443');

    final demo = page.events[1];
    expect(demo.allDay, isTrue);
    expect(demo.start, DateTime(2026, 11, 24));
    expect(demo.end, DateTime(2026, 11, 26));
    expect(demo.location, 'SIT@Punggol E2-03');
    expect(demo.url.toString(), 'https://xsite.singaporetech.edu.sg/d2l/le/calendar/213443');

    final talk = page.events[2];
    expect(talk.kind, LmsEventKind.event);
    expect(talk.url.host, 'xsite.singaporetech.edu.sg');
    expect(talk.url.scheme, 'https');
  });

  test('reads update counts; -1 (not asked) and junk count as none', () {
    final page = parseMyUpdates(jsonEncode({
      'Objects': [
        {
          'OrgUnitId': '213443',
          'UserId': '1',
          'UnreadDiscussions': 3,
          'UnapprovedDiscussions': -1,
          'UnreadAssignmentFeedback': 1,
          'UnattemptedQuizzes': 2,
          'UnreadAssignmentSubmissions': -1,
          'UngradedQuizzes': -1,
        },
        {'OrgUnitId': 213390, 'UnreadDiscussions': -1, 'UnreadAssignmentFeedback': 'x'},
        {'UnreadDiscussions': 5},
      ],
      'Next': null,
    }));
    expect(page.updates.keys, ['213443', '213390']);
    final inf = page.updates['213443']!;
    expect([inf.unreadDiscussions, inf.unreadFeedback, inf.unattemptedQuizzes], [3, 1, 2]);
    expect(inf.total, 6);
    expect(inf.summary, '3 unread discussions, 1 new assignment feedback, 2 quizzes to attempt');
    expect(page.updates['213390']!.isEmpty, isTrue);

    final one = parseCourseUpdates(jsonEncode({'OrgUnitId': '1', 'UnattemptedQuizzes': 1, 'UnreadDiscussions': 0}));
    expect(one.unattemptedQuizzes, 1);
    expect(one.summary, '1 quiz to attempt');
  });

  group('agenda', () {
    final from = DateTime(2026, 11, 20);
    final to = DateTime(2026, 12, 18);
    LmsEvent ev(int id, DateTime start, {DateTime? end, bool allDay = false, LmsRecurrence? r}) => LmsEvent(
        orgUnitId: '1',
        id: id,
        title: 'E$id',
        start: start,
        end: end,
        allDay: allDay,
        recurrence: r,
        url: Uri.parse('https://xsite.singaporetech.edu.sg/d2l/le/calendar/1'));

    test('groups by day, all-day first then by time; ongoing ones show today', () {
      final days = agenda([
        ev(1, DateTime(2026, 11, 21, 14)),
        ev(2, DateTime(2026, 11, 21, 9)),
        ev(3, DateTime(2026, 11, 21), end: DateTime(2026, 11, 22), allDay: true),
        // Started yesterday, still on.
        ev(4, DateTime(2026, 11, 19), end: DateTime(2026, 11, 23), allDay: true),
        // Over before the window.
        ev(5, DateTime(2026, 11, 18, 9), end: DateTime(2026, 11, 18, 10)),
        // After it.
        ev(6, DateTime(2026, 12, 20)),
      ], from, to);
      expect(days.map((d) => d.day), [DateTime(2026, 11, 20), DateTime(2026, 11, 21)]);
      expect(days.first.events.map((e) => e.id), [4]);
      expect(days.last.events.map((e) => e.id), [3, 2, 1]);
    });

    test('weekly repeats spread over the window, until their end', () {
      final weekly = ev(7, DateTime(2026, 11, 3, 10), end: DateTime(2026, 11, 3, 12),
          r: LmsRecurrence(type: 3, weekdays: {DateTime.tuesday, DateTime.thursday}, until: DateTime(2026, 12, 4)));
      final days = agenda([weekly], from, to);
      expect(days.map((d) => '${d.day.month}/${d.day.day}'), ['11/24', '11/26', '12/1', '12/3']);
      expect(days.first.events.single.start, DateTime(2026, 11, 24, 10));
      expect(days.first.events.single.end, DateTime(2026, 11, 24, 12));
    });

    test('one course only', () {
      final a = LmsAgenda(from, to, agenda([ev(1, DateTime(2026, 11, 21, 9))], from, to));
      expect(a.count, 1);
      expect(a.forCourse('1').count, 1);
      expect(a.forCourse('2').days, isEmpty);
    });
  });

  group('requests', () {
    late List<Uri> asked;
    late LmsService service;
    late Map<String, String> replies;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      asked = [];
      replies = {};
      final mock = MockClient((request) async {
        asked.add(request.url);
        final body = replies[request.url.path + (request.url.queryParameters['page'] ?? '')];
        if (body == null) return http.Response('not found', 404, request: request);
        return http.Response(body, 200, headers: {'content-type': 'application/json'}, request: request);
      });
      service = LmsService(AuthService(SessionClient(mock), SecureStorage()));
    });

    test('calendar: one request for all courses, with the window, following pages', () async {
      const path = '/d2l/api/le/1.75/calendar/events/myEvents/';
      replies[path] = jsonEncode({
        'Objects': [
          _event(1, 'First', start: '2026-11-21T01:00:00.000Z'),
        ],
        'Next': '$path?page=2',
      });
      replies['${path}2'] = jsonEncode({
        'Objects': [
          _event(2, 'Second', start: '2026-11-22T01:00:00.000Z'),
        ],
        'Next': null,
      });
      final from = DateTime.utc(2026, 11, 19, 16), to = DateTime.utc(2026, 12, 17, 16);

      final events = await service.calendar.events(['213443', '213390'], from, to);

      expect(events.map((e) => e.title), ['First', 'Second']);
      expect(asked, hasLength(2));
      final first = asked.first;
      expect(first.host, 'xsite.singaporetech.edu.sg');
      expect(first.path, path);
      expect(first.queryParameters, {
        'orgUnitIdsCSV': '213443,213390',
        'startDateTime': '2026-11-19T16:00:00.000Z',
        'endDateTime': '2026-12-17T16:00:00.000Z',
      });
      expect(asked.every((u) => u.scheme == 'https' && u.host == 'xsite.singaporetech.edu.sg'), isTrue);
    });

    test('a next page that leaves xSiTe is refused', () async {
      replies['/d2l/api/le/1.75/calendar/events/myEvents/'] =
          jsonEncode({'Objects': [], 'Next': 'https://evil.example.com/more'});
      await expectLater(
          service.calendar.events(['1'], DateTime(2026, 11, 20), DateTime(2026, 12, 18)), throwsFormatException);
      expect(asked, hasLength(1));
    });

    test('updates: all courses in one request, or one course', () async {
      replies['/d2l/api/le/1.75/updates/myUpdates/'] = jsonEncode({
        'Objects': [
          {'OrgUnitId': 213443, 'UnreadDiscussions': 2, 'UnreadAssignmentFeedback': 0, 'UnattemptedQuizzes': 1},
        ],
        'Next': null,
      });
      replies['/d2l/api/le/1.75/213443/updates/myUpdates'] =
          jsonEncode({'OrgUnitId': 213443, 'UnreadAssignmentFeedback': 4});

      final all = await service.calendar.updates(['213443', '213390']);
      expect(all['213443']!.total, 3);
      expect(asked.single.path, '/d2l/api/le/1.75/updates/myUpdates/');
      expect(asked.single.queryParameters, {'orgUnitIdsCSV': '213443,213390'});

      final one = await service.calendar.courseUpdates('213443');
      expect(one.unreadFeedback, 4);
      expect(asked.last.toString(), 'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/213443/updates/myUpdates');
    });
  });
}
