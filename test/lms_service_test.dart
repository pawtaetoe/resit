import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/data/lms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _course(String id, String name, String code, {String last = '2026-11-05T09:22:10.060Z'}) => {
      'OrgUnitId': id,
      'TypeId': 3,
      'Name': name,
      'Code': code,
      'IsActive': true,
      'StartDate': '2026-08-23T16:00:00.000Z',
      'EndDate': '2030-12-30T16:00:00.000Z',
      'FormattedImageLink': '/d2l/api/lp/1.47/courses/$id/image?autoSelectImage=true',
      'SemesterName': '2026/27 Trimester 1',
      'CanAccessCourse': true,
      'LastAccessed': last,
    };

// The shape of xSiTe's "My Courses" reply (from the user's capture).
final _myCourses = jsonEncode({
  'Courses': [
    _course('214475', 'USI2001-Social Innovation Project-W1 [2026/27 T1]', 'SIT-2610-USI2001-W1'),
    _course('213443', 'INF2004-Embedded Systems Programming [2026/27 T1]', 'SIT-2610-INF2004',
        last: '2026-11-07T09:04:48.870Z'),
    _course('213390', 'CSC2101-Professional Software Development and Team Project 1 [2026/27 T1]', 'SIT-2610-CSC2101',
        last: '2026-11-06T17:04:58.477Z'),
  ],
  'Bookmark': null,
  'Sort': 'current',
});

Map<String, Object?> _item(int id, String title, int done) =>
    {'OrgUnitId': '213443', 'UserId': '1', 'ObjectId': id, 'Title': title, 'RequiredItems': 1, 'CompletedItems': done};

// The shape of the content completion reply (from the user's capture).
final _completions = jsonEncode({
  'Objects': [
    _item(977079, 'RP-008312-DS-2-pico-w-datasheet', 0),
    _item(977492, 'barr_c_coding_standard_2018', 1),
    _item(978769, 'W1 Introduction to Embedded System', 1),
    _item(1004199, 'W10 Optimisations', 0),
  ],
  'Next': null,
});

Map<String, Object?> _topic(int id, String title, String type, String url, {bool unread = true, String text = ''}) => {
      'IsHidden': false,
      'SortOrder': id,
      'TopicId': id,
      'TypeIdentifier': type,
      'Title': title,
      'Unread': unread,
      'Url': url,
      'Description': {'Text': text, 'Html': ''},
    };

// The shape of a course's table of contents (from the user's capture).
final _toc = jsonEncode({
  'Modules': [
    {
      'IsHidden': false,
      'SortOrder': 476,
      'ModuleId': 978766,
      'Title': 'Laboratory',
      'Modules': [],
      'Topics': [_topic(978767, 'INF2004 Labs', 'Link', 'https://github.com/sirfonzie/INF2004', unread: false)],
    },
    {
      'IsHidden': false,
      'SortOrder': -254,
      'ModuleId': 977071,
      'Title': 'Lecture',
      'Modules': [
        {
          'IsHidden': false,
          'SortOrder': -41,
          'ModuleId': 978776,
          'Title': 'External Resources',
          'Modules': [],
          'Topics': [_topic(978777, 'Embedded C Basics', 'Link', 'https://www.youtube.com/playlist?list=x')],
        },
      ],
      'Topics': [
        _topic(1004199, 'W10 Optimisations', 'File', '/content/enforced/213443-SIT-2610-INF2004/W10 Optimisations.pdf'),
        _topic(984035, 'W0_Module Overview', 'File', '/content/enforced/213443-SIT-2610-INF2004/W0_Module Overview.pdf',
            unread: false, text: 'Read first'),
        {..._topic(1, 'Hidden draft', 'File', '/x.pdf'), 'IsHidden': true},
      ],
    },
  ],
});

void main() {
  test('reads the content: folders in course order, items in each, hidden ones left out', () {
    final modules = parseToc('213443', _toc);
    expect(modules.map((m) => m.title), ['Lecture', 'Laboratory']);
    final lecture = modules.first;
    expect(lecture.topics.map((t) => t.title), ['W0_Module Overview', 'W10 Optimisations']);
    expect(lecture.modules.single.title, 'External Resources');
    expect(lecture.allTopics, hasLength(3));

    final overview = lecture.topics.first;
    expect(overview.extension, 'pdf');
    expect(overview.unread, isFalse);
    expect(overview.description, 'Read first');
    // Files open on xSiTe (which counts them as viewed); links open directly.
    expect(overview.openUrl.toString(),
        'https://xsite.singaporetech.edu.sg/d2l/le/content/213443/viewContent/984035/View');
    expect(modules.last.topics.single.openUrl.toString(), 'https://github.com/sirfonzie/INF2004');
  });

  test('reads courses: code, title and term from the name', () {
    final courses = parseMyCourses(_myCourses);
    expect(courses, hasLength(3));
    final usi = courses.first;
    expect(usi.courseCode, 'USI2001');
    expect(usi.title, 'Social Innovation Project-W1');
    expect(usi.termLabel, '2026/27 T1');
    expect(usi.homeUrl.toString(), 'https://xsite.singaporetech.edu.sg/d2l/home/214475');
    final csc = courses.last;
    expect(csc.title, 'Professional Software Development and Team Project 1');
  });

  test('a name without a course code falls back to the code field', () {
    final c = LmsCourse.fromJson({'OrgUnitId': '1', 'Name': 'SIT Library Orientation', 'Code': 'SIT-LIB-ORIENT'});
    expect(c.courseCode, 'ORIENT');
    expect(c.title, 'SIT Library Orientation');
  });

  test('sorts the most recently opened course first within a term', () {
    final sorted = sortCourses(parseMyCourses(_myCourses));
    expect(sorted.map((c) => c.courseCode), ['INF2004', 'CSC2101', 'USI2001']);
  });

  test('progress counts done items and lists what is left', () {
    final p = CourseProgress(parseCompletions(_completions).items);
    expect(p.required, 4);
    expect(p.completed, 2);
    expect(p.fraction, 0.5);
    expect(p.todo.map((i) => i.title), ['RP-008312-DS-2-pico-w-datasheet', 'W10 Optimisations']);
    expect(p.todo.first.url.toString(),
        'https://xsite.singaporetech.edu.sg/d2l/le/content/213443/viewContent/977079/View');
  });

  test('signs in to xSiTe through SIT single sign-on, then reads the courses', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final adfs = Uri.parse('https://fs.singaporetech.edu.sg/adfs/ls/?SAMLRequest=abc');
    var signedIn = false;
    final mock = MockClient((request) async {
      final url = request.url;
      if (url.host == 'xsite.singaporetech.edu.sg' && url.path == '/d2l/le/manageCourses/api/mycourses') {
        return signedIn
            ? http.Response(_myCourses, 200, headers: {'content-type': 'application/json'}, request: request)
            // Not signed in: xSiTe shows its login page.
            : http.Response('<html>Login</html>', 200,
                request: http.Request('GET', Uri.parse('https://xsite.singaporetech.edu.sg/d2l/loginh/')));
      }
      if (url.path == '/d2l/lp/auth/saml/login') {
        // ADFS already knows the user: it answers with the SAML hand-off form.
        return http.Response(
            "<form method='post' action='https://xsite.singaporetech.edu.sg/d2l/lp/auth/login/samlLogin.d2l'>"
            "<input name='SAMLResponse' value='xyz'><input name='RelayState' value='/d2l/home'></form>",
            200,
            request: http.Request('GET', adfs));
      }
      if (request.method == 'POST' && url.path == '/d2l/lp/auth/login/samlLogin.d2l') {
        expect(request.bodyFields['SAMLResponse'], 'xyz');
        signedIn = true;
        return http.Response('', 200, request: request);
      }
      return http.Response('not found', 404, request: request);
    });
    final service = LmsService(AuthService(SessionClient(mock), SecureStorage()));

    final courses = await service.courses();

    expect(signedIn, isTrue);
    expect(courses.map((c) => c.courseCode), ['INF2004', 'CSC2101', 'USI2001']);
  });
}
