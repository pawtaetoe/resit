import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/data/lms_activities.dart';
import 'package:resit/features/lms/data/lms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reply shapes from Brightspace's API documentation (Valence LE 1.75 / LP 1.47).

final _news = jsonEncode([
  {
    'Id': 11,
    'IsHidden': false,
    'IsPublished': true,
    'Title': 'Week 10 lab moved',
    'Body': {'Text': '', 'Html': '<p>The lab is in <b>E2-05-14</b>&nbsp;this week.</p><p>Bring your Pico.</p>'},
    'StartDate': '2026-11-02T01:00:00.000Z',
    'Attachments': [
      {'FileId': 1, 'FileName': 'map.pdf'}
    ],
  },
  {'Id': 12, 'IsHidden': true, 'Title': 'Draft', 'Body': {'Text': 'x'}, 'StartDate': '2026-11-05T01:00:00.000Z'},
  {'Id': 10, 'Title': 'Welcome', 'Body': {'Text': 'Hello all'}, 'StartDate': '2026-08-25T01:00:00.000Z'},
]);

final _folders = jsonEncode([
  {
    'Id': 501,
    'Name': 'Lab 3 report',
    'CustomInstructions': {'Text': 'Submit as PDF.', 'Html': ''},
    'Availability': {'StartDate': null, 'EndDate': '2026-11-21T15:59:00.000Z'},
    'DueDate': '2026-11-20T15:59:00.000Z',
    'Assessment': {'ScoreDenominator': 20},
    'GradeItemId': 9001,
    'DropboxType': 2,
    'IsHidden': false,
  },
  {'Id': 502, 'Name': 'Project report', 'DueDate': '2026-12-05T15:59:00.000Z', 'DropboxType': 1, 'IsHidden': false},
  {'Id': 503, 'Name': 'Hidden folder', 'IsHidden': true},
]);

final _quizzes = jsonEncode({
  'Objects': [
    {
      'QuizId': 71,
      'Name': 'Week 9 quiz',
      'IsActive': true,
      'DueDate': '2026-11-15T15:59:00.000Z',
      'EndDate': '2026-11-16T15:59:00.000Z',
      'AttemptsAllowed': {'IsUnlimited': false, 'NumberOfAttemptsAllowed': 2},
      'SubmissionTimeLimit': {'IsEnforced': true, 'TimeLimitValue': 30},
      'GradeItemId': 9002,
      'Description': {
        'Text': {'Text': 'Covers ADC and timers.', 'Html': ''},
        'IsDisplayed': true
      },
    },
    {'QuizId': 72, 'Name': 'Inactive', 'IsActive': false},
  ],
  'Next': null,
});

final _grades = jsonEncode([
  {
    'GradeObjectIdentifier': '9002',
    'GradeObjectName': 'Week 9 quiz',
    'GradeObjectTypeName': 'Numeric',
    'DisplayedGrade': '8 / 10',
    'PointsNumerator': 8,
    'PointsDenominator': 10,
    'WeightedNumerator': 4,
    'WeightedDenominator': 5,
    'Comments': {'Text': 'Good work', 'Html': ''},
  },
  {'GradeObjectIdentifier': '1', 'GradeObjectName': 'Labs', 'GradeObjectTypeName': 'Category'},
]);

void main() {
  test('announcements: newest first, hidden ones left out, HTML turned into text', () {
    final list = parseAnnouncements(_news);
    expect(list.map((a) => a.title), ['Week 10 lab moved', 'Welcome']);
    expect(list.first.body, 'The lab is in E2-05-14 this week.\nBring your Pico.');
    expect(list.first.attachments, 1);
  });

  test('assignments: deadlines, group folders, hidden ones left out, submissions', () {
    final list = parseAssignments('213443', _folders);
    expect(list.map((a) => a.name), ['Lab 3 report', 'Project report']);
    final lab = list.first;
    expect(lab.outOf, 20);
    expect(lab.gradeItemId, 9001);
    expect(lab.isGroup, isFalse);
    expect(lab.instructions, 'Submit as PDF.');
    expect(lab.endDate, DateTime.parse('2026-11-21T15:59:00.000Z').toLocal());
    expect(list.last.isGroup, isTrue);

    final subs = parseMySubmissions(jsonEncode([
      {'Id': 1, 'SubmissionDate': '2026-11-10T03:00:00.000Z'},
      {'Id': 2, 'SubmissionDate': '2026-11-12T03:00:00.000Z'},
    ]));
    expect(subs.first, DateTime.parse('2026-11-12T03:00:00.000Z').toLocal());
    // The EntityDropBox shape (submissions nested) reads the same.
    expect(
        parseMySubmissions(jsonEncode([
          {
            'Submissions': [
              {'SubmissionDate': '2026-11-12T03:00:00.000Z'}
            ]
          }
        ])),
        hasLength(1));
  });

  test('quizzes: attempts, time limit, description; inactive ones left out', () {
    final r = parseQuizzes('213443', _quizzes);
    expect(r.next, isNull);
    final q = r.quizzes.single;
    expect(q.name, 'Week 9 quiz');
    expect(q.attemptsAllowed, 2);
    expect(q.timeLimit, 30);
    expect(q.description, 'Covers ADC and timers.');
    expect(q.url.toString(), contains('qi=71'));
  });

  test('grades: categories left out; a quiz finds its grade by grade item', () {
    final g = CourseGrades(parseGrades(_grades));
    expect(g.items, hasLength(1));
    expect(g.forItem(9002)?.summary, '8 / 10');
    expect(g.forItem(9002)?.comment, 'Good work');
    expect(g.forItem(1234), isNull);
    expect(GradeEntry(name: 'x', points: 17, outOf: 20).summary, '17 / 20');
  });

  test('due soon: not-yet-submitted work and quizzes in the next two weeks, soonest first', () {
    final now = DateTime.parse('2026-11-14T00:00:00.000Z').toLocal();
    final assignments = parseAssignments('1', _folders);
    final quizzes = parseQuizzes('1', _quizzes).quizzes;
    final due = dueSoon('INF2004', assignments, quizzes, now);
    expect(due.map((d) => d.title), ['Week 9 quiz', 'Lab 3 report']);

    // Submitted work drops off the list.
    final submitted = [assignments.first.withSubmissions([now]), assignments.last];
    expect(dueSoon('INF2004', submitted, const [], now).map((d) => d.title), isEmpty);
  });

  group('service', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('a tool closed to students reads as "not available", without signing in again', () async {
      var ssoStarts = 0;
      final mock = MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/news/')) return http.Response(_news, 200, headers: {'content-type': 'application/json'}, request: request);
        if (path.contains('/quizzes/')) return http.Response('{"Errors":[]}', 403, request: request);
        if (path == '/d2l/lp/auth/saml/login') ssoStarts++;
        return http.Response('not found', 404, request: request);
      });
      final service = LmsService(AuthService(SessionClient(mock), SecureStorage()));

      expect(await service.announcements('1'), hasLength(2));
      await expectLater(service.quizzes('1'), throwsA(isA<LmsUnavailableException>()));
      expect(ssoStarts, 0);
    });

    test('groups: only yours, with members named from the class list', () async {
      final replies = {
        '/d2l/api/lp/1.47/users/whoami': {'Identifier': '52868', 'FirstName': 'Kung'},
        '/d2l/api/lp/1.47/1/groupcategories/': [
          {'GroupCategoryId': 5, 'Name': 'Project Groups'},
          {'GroupCategoryId': 6, 'Name': 'Lab Groups'},
        ],
        '/d2l/api/lp/1.47/1/groupcategories/5/groups/': [
          {'GroupId': 1, 'Name': 'P1', 'Enrollments': [1, 2]},
          {'GroupId': 2, 'Name': 'P2', 'Enrollments': [52868, 3]},
        ],
        '/d2l/api/lp/1.47/1/groupcategories/6/groups/': [
          {'GroupId': 3, 'Name': 'L1', 'Enrollments': [4]},
        ],
        '/d2l/api/le/1.75/1/classlist/': [
          {'Identifier': '52868', 'DisplayName': 'Kung Chih Chia'},
          {'Identifier': '3', 'DisplayName': 'Alex Tan'},
        ],
      };
      final mock = MockClient((request) async {
        final body = replies[request.url.path];
        return body == null
            ? http.Response('nf', 404, request: request)
            : http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}, request: request);
      });
      final service = LmsService(AuthService(SessionClient(mock), SecureStorage()));

      final groups = await service.groups('1');
      expect(groups.single.category, 'Project Groups');
      expect(groups.single.name, 'P2');
      expect(groups.single.members.map((m) => m.name), ['Kung Chih Chia (you)', 'Alex Tan']);
    });
  });
}
