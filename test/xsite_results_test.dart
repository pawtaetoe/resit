import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/results_parsers.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reply shapes from Brightspace's API documentation (Valence LE 1.75;
// rubrics LE 1.93): Dropbox.EntityDropbox / DropboxFeedbackOut,
// Rubric.Rubric / RubricAssessment, Quiz.QuizAttemptData.

Map<String, Object?> _feedbackBlock({bool graded = true}) => {
      'Score': 17.5,
      'Feedback': {'Text': '', 'Html': '<p>Clear report.</p><p>Cite your sources.</p>'},
      'RubricAssessments': [
        {
          'RubricId': 31,
          'UserId': 52868,
          'ObjectType': 'Dropbox',
          'ObjectId': 501,
          'OverallOutcome': {'LevelId': 900, 'Score': 17.5, 'Feedback': {'Text': 'Solid', 'Html': ''}},
          'CriteriaOutcome': [
            {'CriterionId': 702, 'LevelId': 802, 'Score': 7.5, 'Feedback': {'Text': 'Tidy', 'Html': ''}},
            {'CriterionId': 701, 'LevelId': 801, 'Score': 10, 'Feedback': {'Text': '', 'Html': ''}},
          ],
        }
      ],
      'IsGraded': graded,
      'Files': [
        {'FileId': 5, 'FileName': 'marked-report.pdf', 'Size': 12345}
      ],
      'Links': [
        {'Type': 'MediaContent', 'LinkId': 6, 'LinkName': 'Audio feedback', 'Href': null}
      ],
      'GradedSymbol': null,
    };

Map<String, Object?> _entityDropbox({Map<String, Object?>? feedback}) => {
      'Entity': {'EntityId': 52868, 'EntityType': 'User', 'DisplayName': 'Kung Chih Chia'},
      'Status': 'Published',
      'Feedback': feedback,
      'Submissions': [
        {'Id': 1, 'SubmissionDate': '2026-11-10T03:00:00.000Z', 'Files': []}
      ],
    };

final _rubrics = [
  {
    'RubricId': 31,
    'Name': 'Lab report rubric',
    'RubricType': 1,
    'Visibility': 0,
    'IsScoreVisibleToAssessedUsers': true,
    'CriteriaGroups': [
      {
        'Name': 'Criteria',
        'Levels': [
          {'Id': 801, 'Name': 'Excellent', 'Points': 10},
          {'Id': 802, 'Name': 'Good', 'Points': 7.5},
        ],
        'Criteria': [
          {
            'Id': 701,
            'Name': 'Analysis',
            'Cells': [
              {'Points': 10},
              {'Points': 7.5}
            ]
          },
          {
            'Id': 702,
            'Name': 'Presentation',
            'Cells': [
              {'Points': 10},
              {'Points': 7.5}
            ]
          },
        ],
      }
    ],
    'OverallLevels': [
      {'Id': 900, 'Name': 'Distinction', 'RangeStart': 16},
    ],
  }
];

Map<String, Object?> _attempt(int n, {bool published = true, String? completed = '2026-11-03T06:05:00.000Z', int user = 52868}) => {
      'AttemptId': 100 + n,
      'QuizId': 71,
      'UserId': user,
      'AttemptNumber': n,
      'Score': 8.5,
      'Started': '2026-11-03T05:40:00.000Z',
      'Completed': completed,
      'AttemptFeedback': {'Text': 'Review timers', 'Html': ''},
      'IsPublished': published,
    };

final _lab = Assignment(orgUnitId: '1', id: 501, name: 'Lab 3 report', outOf: 20);
final _quiz = Quiz(orgUnitId: '1', id: 71, name: 'Week 9 quiz');

void main() {
  group('parsers', () {
    test('released feedback: score, comments as text, rubric with names, attachment names', () {
      final defs = {for (final r in parseRubrics(jsonEncode(_rubrics))) r.id: r};
      final f = feedbackFromJson(_feedbackBlock(), rubrics: defs)!;
      expect(f.score, 17.5);
      expect(f.scoreLabel(20), '17.5 / 20');
      expect(f.comments, 'Clear report.\nCite your sources.');
      expect(f.attachments, ['marked-report.pdf', 'Audio feedback']);
      final r = f.rubrics.single;
      expect(r.name, 'Lab report rubric');
      expect(r.overallLevel, 'Distinction');
      expect(r.feedback, 'Solid');
      // In the rubric's order, not the reply's.
      expect(r.criteria.map((c) => c.criterion), ['Analysis', 'Presentation']);
      expect(r.criteria.map((c) => c.level), ['Excellent', 'Good']);
      expect(r.criteria.last.outOf, 10);
      expect(r.criteria.last.feedback, 'Tidy');
    });

    test('draft feedback is never shown', () {
      expect(feedbackFromJson(_feedbackBlock(graded: false)), isNull);
      expect(feedbackFromJson({'Score': 3}), isNull, reason: 'IsGraded missing');
    });

    test('a rubric that cannot be read still shows its results, generically named', () {
      final r = feedbackFromJson(_feedbackBlock())!.rubrics.single;
      expect(r.name, 'Rubric');
      expect(r.criteria.map((c) => c.criterion), ['Criterion 1', 'Criterion 2']);
      expect(r.criteria.first.level, isNull);
    });

    test('a rubric never visible to students is left out; hidden scores are flagged', () {
      final never = [
        {..._rubrics.first, 'Visibility': 2}
      ];
      final defs = {for (final r in parseRubrics(jsonEncode(never))) r.id: r};
      expect(feedbackFromJson(_feedbackBlock(), rubrics: defs)!.rubrics, isEmpty);
      final noScores = [
        {..._rubrics.first, 'IsScoreVisibleToAssessedUsers': false}
      ];
      final defs2 = {for (final r in parseRubrics(jsonEncode(noScores))) r.id: r};
      expect(feedbackFromJson(_feedbackBlock(), rubrics: defs2)!.rubrics.single.showScores, isFalse);
    });

    test('odd values are skipped, not fatal', () {
      final f = feedbackFromJson({
        'IsGraded': true,
        'Score': 'x',
        'GradedSymbol': 'A',
        'Feedback': 7,
        'Files': [null, 'a', {'FileName': 3}, {'FileName': 'ok.pdf'}],
        'RubricAssessments': 'nope',
      })!;
      expect(f.score, isNull);
      expect(f.scoreLabel(20), 'A');
      expect(f.attachments, ['ok.pdf']);
      expect(parseEntityDropboxes(jsonEncode([_entityDropbox(), 3, {'Entity': 'x'}])).map((e) => e.entity?.id),
          ['52868', null]);
    });

    test('quiz attempts: in order, scores only when released, other users left out', () {
      final r = parseQuizAttempts(
          jsonEncode({
            'Objects': [
              _attempt(2, published: false, completed: null),
              _attempt(1),
              _attempt(1, user: 9),
              {'AttemptNumber': 'x'},
            ],
            'Next': null,
          }),
          userId: '52868');
      expect(r.next, isNull);
      expect(r.attempts.map((a) => a.number), [1, 2]);
      expect(r.attempts.first.released, isTrue);
      expect(r.attempts.first.score, 8.5);
      expect(r.attempts.first.feedback, 'Review timers');
      expect(r.attempts.last.released, isFalse);
      expect(r.attempts.last.score, isNull);
      expect(r.attempts.last.feedback, isEmpty);
      expect(r.attempts.last.inProgress, isTrue);
    });

    test('the feedback page is on xSiTe, over https', () {
      final url = feedbackPage(_lab, const FeedbackEntity(isGroup: true, id: '44'));
      expect(url.scheme, 'https');
      expect(url.host, 'xsite.singaporetech.edu.sg');
      expect(url.queryParameters, containsPair('db', '501'));
      expect(url.queryParameters, containsPair('grpid', '44'));
    });
  });

  group('service', () {
    late List<Uri> asked;
    late Map<String, ({int status, Object? body})> replies;
    late LmsService service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      asked = [];
      replies = {'/d2l/api/lp/1.47/users/whoami': (status: 200, body: {'Identifier': '52868'})};
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        asked.add(request.url);
        final r = replies[request.url.path];
        if (r == null) return http.Response('nf', 404, request: request);
        return http.Response(jsonEncode(r.body), r.status, headers: {'content-type': 'application/json'}, request: request);
      });
      service = LmsService(AuthService(SessionClient(mock), SecureStorage()));
    });

    test('feedback comes with your submissions; rubric names from the folder rubrics', () async {
      replies['/d2l/api/le/1.75/1/dropbox/folders/501/submissions/mysubmissions/'] =
          (status: 200, body: [_entityDropbox(feedback: _feedbackBlock())]);
      replies['/d2l/api/le/1.93/1/rubrics/'] = (status: 200, body: _rubrics);

      final f = (await service.feedback(_lab))!;

      expect(f.rubrics.single.criteria.first.criterion, 'Analysis');
      expect(f.entity?.id, '52868');
      expect(asked.map((u) => u.toString()), [
        'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/1/dropbox/folders/501/submissions/mysubmissions/',
        'https://xsite.singaporetech.edu.sg/d2l/api/le/1.93/1/rubrics/?objectType=Dropbox&objectId=501',
      ]);
    });

    test('with nothing submitted, your feedback entry is asked for; drafts and 404s show nothing', () async {
      replies['/d2l/api/le/1.75/1/dropbox/folders/501/submissions/mysubmissions/'] = (status: 200, body: <Object>[]);
      replies['/d2l/api/le/1.75/1/dropbox/folders/501/feedback/user/52868'] =
          (status: 200, body: {..._feedbackBlock(), 'RubricAssessments': <Object>[]});

      expect((await service.feedback(_lab))!.comments, startsWith('Clear report.'));
      expect(asked.map((u) => u.path), [
        '/d2l/api/le/1.75/1/dropbox/folders/501/submissions/mysubmissions/',
        '/d2l/api/lp/1.47/users/whoami',
        '/d2l/api/le/1.75/1/dropbox/folders/501/feedback/user/52868',
      ]);

      replies['/d2l/api/le/1.75/1/dropbox/folders/501/feedback/user/52868'] = (status: 200, body: _feedbackBlock(graded: false));
      expect(await service.feedback(_lab), isNull);

      replies.remove('/d2l/api/le/1.75/1/dropbox/folders/501/feedback/user/52868');
      expect(await service.feedback(_lab), isNull);
      expect(asked.every((u) => u.host == 'xsite.singaporetech.edu.sg' && u.scheme == 'https'), isTrue);
    });

    test('quiz attempts: only yours, page by page, staying on xSiTe', () async {
      replies['/d2l/api/le/1.75/1/quizzes/71/attempts/'] = (
        status: 200,
        body: {
          'Objects': [_attempt(1)],
          'Next': 'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/1/quizzes/71/attempts/page2',
        }
      );
      replies['/d2l/api/le/1.75/1/quizzes/71/attempts/page2'] = (
        status: 200,
        body: {
          'Objects': [_attempt(2, published: false)],
          'Next': null,
        }
      );

      final attempts = await service.quizAttempts(_quiz);

      expect(attempts.map((a) => a.number), [1, 2]);
      expect(asked.map((u) => u.toString()), [
        'https://xsite.singaporetech.edu.sg/d2l/api/lp/1.47/users/whoami',
        'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/1/quizzes/71/attempts/?userId=52868',
        'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/1/quizzes/71/attempts/page2',
      ]);

      // A next page elsewhere is refused.
      replies['/d2l/api/le/1.75/1/quizzes/71/attempts/'] = (
        status: 200,
        body: {'Objects': <Object>[], 'Next': 'https://example.com/steal'}
      );
      await expectLater(service.quizAttempts(_quiz), throwsFormatException);
      expect(asked.where((u) => u.host != 'xsite.singaporetech.edu.sg'), isEmpty);
    });

    test('attempts closed to students read as "not available"', () async {
      replies['/d2l/api/le/1.75/1/quizzes/71/attempts/'] = (status: 403, body: {'Errors': <Object>[]});
      await expectLater(service.quizAttempts(_quiz), throwsA(isA<LmsUnavailableException>()));
    });
  });
}
