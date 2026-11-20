import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/discussion_parsers.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reply shapes from Brightspace's API documentation (Discussions, LE 1.75).

final _now = DateTime.parse('2026-11-20T04:00:00.000Z');

Map<String, Object?> _forum(int id, String name, {bool hidden = false, String? start, String? startType}) => {
      'ForumId': id,
      'StartDate': start,
      'EndDate': null,
      'PostStartDate': null,
      'PostEndDate': null,
      'Name': name,
      'Description': {'Text': '', 'Html': '<p>Ask about the labs.</p>'},
      'ShowDescriptionInTopics': false,
      'AllowAnonymous': false,
      'IsLocked': false,
      'IsHidden': hidden,
      'RequiresApproval': false,
      'DisplayInCalendar': false,
      'DisplayPostDatesInCalendar': false,
      'StartDateAvailabilityType': startType,
      'EndDateAvailabilityType': null,
    };

Map<String, Object?> _topic(int forumId, int id, String name,
        {bool hidden = false, String? start, String? end, String? startType, String? endType, bool mustPost = false}) =>
    {
      'ForumId': forumId,
      'TopicId': id,
      'Name': name,
      'Description': {'Text': 'Post your questions here.', 'Html': ''},
      'StartDate': start,
      'EndDate': end,
      'UnlockStartDate': null,
      'UnlockEndDate': null,
      'IsLocked': false,
      'AllowAnonymousPosts': false,
      'RequiresApproval': false,
      'UnApprovedPostCount': 0,
      'PinnedPostCount': 0,
      'ScoringType': null,
      'IsAutoScore': false,
      'ScoreOutOf': null,
      'IncludeNonScoredValues': false,
      'ScoredCount': 0,
      'RatingsSum': 0,
      'RatingsCount': 0,
      'IsHidden': hidden,
      'MustPostToParticipate': mustPost,
      'RatingType': '0',
      'ActivityId': null,
      'GroupTypeId': null,
      'StartDateAvailabilityType': startType,
      'EndDateAvailabilityType': endType,
    };

Map<String, Object?> _post(int id, int thread, int? parent, String subject, String date,
        {String author = 'Alex Tan', bool read = true, bool deleted = false, bool anonymous = false, String html = ''}) =>
    {
      'ForumId': 1,
      'PostId': id,
      'TopicId': 10,
      'PostingUserId': 5,
      'PostingUserDisplayName': author,
      'ThreadId': thread,
      'ParentPostId': parent,
      'Message': {'Text': html.isEmpty ? 'Body of $subject' : '', 'Html': html},
      'Subject': subject,
      'DatePosted': date,
      'IsAnonymous': anonymous,
      'RequiresApproval': false,
      'IsDeleted': deleted,
      'LastEditedDate': null,
      'LastEditedBy': null,
      'CanRate': false,
      'ReplyPostIds': [],
      'WordCount': 4,
      'AttachmentCount': id == 100 ? 1 : 0,
      'IsRead': read,
    };

final _posts = [
  _post(103, 100, 101, 'Re: Re: Lab 3 timer', '2026-11-12T03:00:00.000Z', read: false),
  _post(200, 200, null, 'Week 10 question', '2026-11-15T02:00:00.000Z',
      author: 'Kim Lee', read: false, html: '<p>Is the &amp; quiz <b>open book</b>?</p>'),
  _post(102, 100, 100, 'Re: Lab 3 timer', '2026-11-11T03:00:00.000Z', anonymous: true),
  _post(101, 100, 100, 'Re: Lab 3 timer', '2026-11-10T05:00:00.000Z'),
  _post(100, 100, null, 'Lab 3 timer', '2026-11-10T03:00:00.000Z'),
  _post(104, 100, 100, 'Removed', '2026-11-13T03:00:00.000Z', deleted: true),
];

void main() {
  test('forums: hidden ones and ones hidden until they open are left out', () {
    final forums = parseForums(
        jsonEncode([
          _forum(1, 'Labs'),
          _forum(2, 'Staff only', hidden: true),
          _forum(3, 'Exam', start: '2026-12-01T00:00:00.000Z', startType: 'Hidden'),
          _forum(4, 'Project', start: '2026-12-01T00:00:00.000Z', startType: 'AccessRestricted'),
        ]),
        now: _now);
    expect(forums.map((f) => f.name), ['Labs', 'Project']);
    expect(forums.first.description, 'Ask about the labs.');
    expect(forums.last.access, TopicAccess.notYetOpen);
  });

  test('topics: hidden ones left out, dates mark them not yet open or closed', () {
    final topics = parseTopics(
        '213443',
        const DiscussionForum(id: 1, name: 'Labs'),
        jsonEncode([
          _topic(1, 10, 'Lab questions'),
          _topic(1, 11, 'Hidden', hidden: true),
          _topic(1, 12, 'Week 13', start: '2026-12-01T00:00:00.000Z', startType: '2'),
          _topic(1, 13, 'Week 12', start: '2026-11-25T00:00:00.000Z'),
          _topic(1, 14, 'Week 1', end: '2026-09-01T00:00:00.000Z', endType: 'SubmissionRestricted'),
          _topic(1, 15, 'Old quiz', end: '2026-09-01T00:00:00.000Z', endType: 'AccessRestricted'),
          _topic(1, 16, 'Reflections', mustPost: true),
          {'Name': 'No id'},
          'junk',
        ]),
        now: _now);
    expect(topics.map((t) => t.name), ['Lab questions', 'Week 12', 'Week 1', 'Old quiz', 'Reflections']);
    expect(topics.map((t) => t.access), [
      TopicAccess.open,
      TopicAccess.notYetOpen,
      TopicAccess.closed,
      TopicAccess.ended,
      TopicAccess.open,
    ]);
    expect(topics.map((t) => t.readable), [true, false, true, false, true]);
    expect(topics.first.description, 'Post your questions here.');
    expect(topics.last.mustPost, isTrue);
    expect(topics.first.url.toString(), 'https://xsite.singaporetech.edu.sg/d2l/le/213443/discussions/topics/10/View');

    // A forum that isn't open yet keeps its topics closed too.
    final later = parseTopics(
        '1',
        DiscussionForum(id: 1, name: 'Project', access: TopicAccess.notYetOpen, accessDate: DateTime(2026, 12)),
        jsonEncode([_topic(1, 10, 'Ideas')]),
        now: _now);
    expect(later.single.access, TopicAccess.notYetOpen);
    expect(later.single.accessDate, DateTime(2026, 12));
  });

  test('posts: threads newest first, replies nested in order, deleted ones left out', () {
    final page = parsePosts(jsonEncode(_posts));
    expect(page.rows, 6);
    expect(page.posts, hasLength(5));
    final topic = TopicPosts.from(page.posts);
    expect(topic.postCount, 5);
    expect(topic.unread, 2);
    expect(topic.lastPost, DateTime.parse('2026-11-15T02:00:00.000Z').toLocal());

    expect(topic.threads.map((t) => t.first.subject), ['Week 10 question', 'Lab 3 timer']);
    final week10 = topic.threads.first.first;
    expect(week10.author, 'Kim Lee');
    expect(week10.body, 'Is the & quiz open book?');
    expect(week10.isUnread, isTrue);

    final lab = topic.threads.last;
    expect(lab.first.attachments, 1);
    expect([for (final r in lab.replies) (r.depth, r.post.id)], [(1, 101), (2, 103), (1, 102)]);
    expect(lab.replies.last.post.author, 'Anonymous');
    expect(lab.lastPost, DateTime.parse('2026-11-12T03:00:00.000Z').toLocal());
  });

  test('posts: a thread whose first post is gone starts at its oldest reply', () {
    final topic = TopicPosts.from(parsePosts(jsonEncode([
      _post(102, 100, 101, 'C', '2026-11-12T03:00:00.000Z'),
      _post(101, 100, 100, 'B', '2026-11-11T03:00:00.000Z'),
    ])).posts);
    final t = topic.threads.single;
    expect(t.first.subject, 'B');
    expect([for (final r in t.replies) (r.depth, r.post.subject)], [(1, 'C')]);
    // No read flags at all: unread unknown.
    expect(TopicPosts.from(const [DiscussionPost(id: 1, threadId: 1)]).unread, isNull);
  });

  group('service', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    http.Response json(http.Request r, Object body) =>
        http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}, request: r);

    test('forums with their topics; a forum without topics (404) is left out', () async {
      final asked = <Uri>[];
      final mock = MockClient((r) async {
        asked.add(r.url);
        expect(r.method, 'GET');
        return switch (r.url.path) {
          '/d2l/api/le/1.75/7/discussions/forums/' => json(r, [_forum(1, 'Labs'), _forum(2, 'Empty')]),
          '/d2l/api/le/1.75/7/discussions/forums/1/topics/' => json(r, [_topic(1, 10, 'Lab questions')]),
          _ => http.Response('{"Errors":[]}', 404, request: r),
        };
      });
      final service = LmsService(AuthService(SessionClient(mock), SecureStorage()));

      final forums = await service.discussions.forums('7');
      expect(forums.single.name, 'Labs');
      expect(forums.single.topics.single.key, (orgUnitId: '7', forumId: 1, topicId: 10));
      expect(asked.map((u) => u.path).toSet(), {
        '/d2l/api/le/1.75/7/discussions/forums/',
        '/d2l/api/le/1.75/7/discussions/forums/1/topics/',
        '/d2l/api/le/1.75/7/discussions/forums/2/topics/',
      });
      expect(asked.every((u) => u.scheme == 'https' && u.host == 'xsite.singaporetech.edu.sg'), isTrue);
    });

    test('posts are read page by page until a short page', () async {
      final asked = <Uri>[];
      final full = [
        for (var i = 1; i <= 200; i++) _post(1000 + i, 1001, i == 1 ? null : 1001, 'P$i', '2026-11-01T00:00:00.000Z'),
      ];
      final mock = MockClient((r) async {
        asked.add(r.url);
        if (r.url.path != '/d2l/api/le/1.75/7/discussions/forums/1/topics/10/posts/') {
          return http.Response('nf', 404, request: r);
        }
        return json(r, r.url.queryParameters['pageNumber'] == '1' ? full : _posts);
      });
      final service = LmsService(AuthService(SessionClient(mock), SecureStorage()));

      final topic = await service.discussions.posts((orgUnitId: '7', forumId: 1, topicId: 10));
      expect(asked.map((u) => u.queryParameters), [
        {'pageSize': '200', 'pageNumber': '1'},
        {'pageSize': '200', 'pageNumber': '2'},
      ]);
      expect(topic.postCount, 205);
      expect(topic.threads, hasLength(3));
      expect(asked.every((u) => u.host == 'xsite.singaporetech.edu.sg'), isTrue);
    });

    test('discussions closed to students read as "not available"', () async {
      final mock = MockClient((r) async {
        if (r.url.path.endsWith('/news/')) return json(r, []);
        return http.Response('{"Errors":[]}', 403, request: r);
      });
      final service = LmsService(AuthService(SessionClient(mock), SecureStorage()));
      await service.announcements('7');
      await expectLater(service.discussions.forums('7'), throwsA(isA<LmsUnavailableException>()));
    });
  });
}
