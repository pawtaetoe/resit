import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/course_extras_parsers.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reply shapes from Brightspace's API documentation (Valence LE 1.75):
// Overview.Overview, ChecklistReadData / CategoryReadData / ItemReadData and
// SurveyReadData, in ObjectListPages ({Next, Objects}).

const _le = 'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/213443';

final _overview = jsonEncode({
  'Description': {'Text': '', 'Html': '<p>Welcome to <b>INF2004</b>.</p><p>Read the syllabus first.</p>'},
  'HasAttachment': true,
});

final _checklistsPage1 = jsonEncode({
  'Next': '$_le/checklists/?bookmark=5',
  'Objects': [
    {'Id': 5, 'Name': 'Getting started', 'Description': {'Text': 'Do these in week 1', 'Html': ''}},
    {'Name': 'No id, skipped'},
  ],
});
final _checklistsPage2 = jsonEncode({
  'Next': null,
  'Objects': [
    {'Id': 6, 'Name': 'Project milestones', 'Description': {'Text': '', 'Html': ''}},
  ],
});
final _categories = jsonEncode({
  'Next': null,
  'Objects': [
    {'CategoryId': 52, 'Name': 'Lab setup', 'Description': {'Text': '', 'Html': ''}, 'SortOrder': 2},
    {'CategoryId': 51, 'Name': 'Read first', 'Description': {'Text': 'Before the first lecture', 'Html': ''}, 'SortOrder': 1},
  ],
});
final _items = jsonEncode({
  'Next': null,
  'Objects': [
    {
      'ChecklistItemId': 503,
      'CategoryId': 52,
      'ChecklistId': 5,
      'Name': 'Install the Pico SDK',
      'Description': {'Text': '', 'Html': '<p>Follow the <i>lab 0</i> guide.</p>'},
      'SortOrder': 1,
      'DueDate': '2026-11-21T15:59:00.000Z',
    },
    {'ChecklistItemId': 502, 'CategoryId': 51, 'ChecklistId': 5, 'Name': 'Read the module guide', 'SortOrder': 2},
    {'ChecklistItemId': 501, 'CategoryId': 51, 'ChecklistId': 5, 'Name': 'Join the Teams channel', 'SortOrder': 1},
    {'ChecklistItemId': 504, 'CategoryId': 99, 'ChecklistId': 5, 'Name': 'Loose item', 'SortOrder': 1},
    {'Name': 'No id, skipped'},
  ],
});

final _surveys = jsonEncode({
  'Next': null,
  'Objects': [
    {
      'SurveyId': 31,
      'Name': 'End of term feedback',
      'SortOrder': 1,
      'IsAnonymous': true,
      'Description': {'Text': {'Text': 'Tell us how it went', 'Html': ''}, 'IsDisplayed': true},
      'IsActive': true,
      'StartDate': '2026-11-01T00:00:00.000Z',
      'EndDate': '2026-12-01T15:59:00.000Z',
    },
    {
      'SurveyId': 32,
      'Name': 'Week 1 check-in',
      'SortOrder': 2,
      'Description': {'Text': {'Text': 'Hidden text', 'Html': ''}, 'IsDisplayed': false},
      'IsActive': true,
      'StartDate': '2026-08-25T00:00:00.000Z',
      'EndDate': '2026-09-01T15:59:00.000Z',
    },
    {'SurveyId': 33, 'Name': 'Draft survey', 'IsActive': false},
    {'SurveyId': 34, 'Name': 'Lab safety', 'IsActive': true, 'EndDate': '2026-11-25T15:59:00.000Z'},
  ],
});

http.Response _json(String body, http.Request r) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'}, request: r);

void main() {
  final now = DateTime.utc(2026, 11, 20, 4);

  group('parsers', () {
    test('overview: plain text from the rich text, and whether a file is attached', () {
      final o = parseOverview(_overview)!;
      expect(o.text, 'Welcome to INF2004.\nRead the syllabus first.');
      expect(o.hasAttachment, isTrue);
      expect(parseOverview(jsonEncode({'Description': {'Text': '', 'Html': ''}, 'HasAttachment': false})), isNull);
      expect(parseOverview('[]'), isNull);
    });

    test('checklist: categories and items in sort order, unknown category last', () {
      final c = withCategories(
        checklistFromJson('213443', (jsonDecode(_checklistsPage1)['Objects'] as List).first as Map<String, Object?>)!,
        parsePage(_categories).rows,
        parsePage(_items).rows,
      );
      expect(c.name, 'Getting started');
      expect(c.description, 'Do these in week 1');
      expect(c.categories.map((x) => x.name), ['Read first', 'Lab setup', '']);
      expect(c.categories.first.items.map((i) => i.name), ['Join the Teams channel', 'Read the module guide']);
      final sdk = c.categories[1].items.single;
      expect(sdk.description, 'Follow the lab 0 guide.');
      expect(sdk.dueDate?.toUtc(), DateTime.utc(2026, 11, 21, 15, 59));
      expect(c.categories.last.items.single.name, 'Loose item');
      expect(c.itemCount, 4);
      expect(c.url.toString(), 'https://xsite.singaporetech.edu.sg/d2l/lms/checklist/checklist.d2l?checklistId=5&ou=213443');
    });

    test('surveys: inactive ones left out, hidden descriptions dropped, open first', () {
      final list = sortSurveys([
        for (final r in parsePage(_surveys).rows)
          if (surveyFromJson('213443', r) case final s?) s,
      ], now);
      expect(list.map((s) => s.name), ['Lab safety', 'End of term feedback', 'Week 1 check-in']);
      expect(list[1].description, 'Tell us how it went');
      expect(list[1].isAnonymous, isTrue);
      expect(list[2].description, '');
      expect(list[2].isClosed(now), isTrue);
      expect(list.first.url.toString(),
          'https://xsite.singaporetech.edu.sg/d2l/lms/survey/user/survey_summary.d2l?si=34&ou=213443');
    });

    test('file names: from Content-Disposition, without folders or odd characters', () {
      expect(downloadName('attachment; filename="W10 Optimisations.pdf"', 'x'), 'W10 Optimisations.pdf');
      expect(downloadName("attachment; filename*=UTF-8''Lab%203%20%E2%80%93%20brief.pdf", 'x'), 'Lab 3 _ brief.pdf');
      expect(downloadName('attachment; filename="../../etc/passwd"', 'x'), 'passwd');
      expect(downloadName('attachment; filename="..."', 'fallback.pdf'), 'fallback.pdf');
      expect(downloadName(null, 'notes.pdf'), 'notes.pdf');
      expect(safeFileName('${'a' * 200}.pdf', 'x'), '${'a' * 116}.pdf');
    });

    test('file type labels and which topics open as documents', () {
      ContentTopic t(String url, {String type = 'File'}) =>
          ContentTopic(orgUnitId: '1', id: 1, title: 't', type: type, url: url);
      expect(fileTypeLabel(t('/content/a.pdf')), 'PDF');
      expect(fileTypeLabel(t('/content/a.pptx')), 'Slides');
      expect(fileTypeLabel(t('/content/a.c')), 'C file');
      expect(fileTypeLabel(t('https://example.com', type: 'Link')), '');
      expect(isDocument(t('/content/a.pdf')), isTrue);
      expect(isDocument(t('/content/a.mp4')), isFalse);
      expect(isDocument(t('/content/a.html')), isFalse);
      expect(fileSizeLabel(2400000), '2.3 MB');
      expect(fileSizeLabel(640 * 1024), '640 KB');
    });
  });

  group('requests', () {
    late List<Uri> asked;
    late bool signedIn;
    late LmsService service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      asked = [];
      signedIn = true;
      final adfs = Uri.parse('https://fs.singaporetech.edu.sg/adfs/ls/?SAMLRequest=abc');
      final mock = MockClient((request) async {
        final url = request.url;
        if (url.path == '/d2l/lp/auth/saml/login') {
          return http.Response(
              "<form method='post' action='https://xsite.singaporetech.edu.sg/d2l/lp/auth/login/samlLogin.d2l'>"
              "<input name='SAMLResponse' value='xyz'><input name='RelayState' value='/d2l/home'></form>",
              200,
              request: http.Request('GET', adfs));
        }
        if (request.method == 'POST' && url.path == '/d2l/lp/auth/login/samlLogin.d2l') {
          signedIn = true;
          return http.Response('', 200, request: request);
        }
        expect(request.method, 'GET');
        asked.add(url);
        if (!signedIn) {
          return http.Response('<html>Login</html>', 200,
              headers: {'content-type': 'text/html'},
              request: http.Request('GET', Uri.parse('https://xsite.singaporetech.edu.sg/d2l/loginh/')));
        }
        final p = url.path.replaceFirst('/d2l/api/le/1.75/213443', '');
        return switch (p) {
          '/overview' => _json(_overview, request),
          '/overview/attachment' || '/content/topics/977079/file' => http.Response.bytes(
              utf8.encode('%PDF-1.7 test'),
              200,
              headers: {
                'content-type': 'application/pdf',
                'content-disposition': 'attachment; filename="W10 Optimisations.pdf"',
              },
              request: request,
            ),
          '/checklists/' => _json(url.queryParameters['bookmark'] == '5' ? _checklistsPage2 : _checklistsPage1, request),
          '/checklists/5/categories/' => _json(_categories, request),
          '/checklists/5/items/' => _json(_items, request),
          '/surveys/' => _json(_surveys, request),
          '/d2l/api/lp/1.47/users/whoami' => _json('{"Identifier":"1"}', request),
          _ => http.Response('forbidden', 403, request: request),
        };
      });
      service = LmsService(AuthService(SessionClient(mock), SecureStorage()), now: () => now);
    });

    test('reads every checklist page, each checklist\'s categories and items, on xSiTe only', () async {
      final lists = await service.extras.checklists('213443');
      expect(lists.map((c) => c.name), ['Getting started', 'Project milestones']);
      expect(lists.first.itemCount, 4);
      // Checklist 6's categories are closed to students: listed without them.
      expect(lists.last.categories, isEmpty);
      expect(asked.map((u) => u.toString()), containsAll([
        '$_le/checklists/',
        '$_le/checklists/?bookmark=5',
        '$_le/checklists/5/categories/',
        '$_le/checklists/5/items/',
        '$_le/checklists/6/categories/',
        '$_le/checklists/6/items/',
      ]));
      expect(asked.every((u) => u.host == 'xsite.singaporetech.edu.sg'), isTrue);
    });

    test('surveys and the overview', () async {
      final surveys = await service.extras.surveys('213443');
      expect(surveys.map((s) => s.id), [34, 31, 32]);
      final overview = await service.extras.overview('213443');
      expect(overview!.hasAttachment, isTrue);
      expect(asked.map((u) => u.toString()), ['$_le/surveys/', '$_le/overview']);
    });

    test('a course without an overview has none, not an error', () async {
      await service.extras.surveys('213443');
      expect(await service.extras.overview('999'), isNull);
    });

    test('a page link that leaves xSiTe is refused', () async {
      final evil = MockClient((r) async => _json(jsonEncode({'Next': 'https://evil.example/x', 'Objects': []}), r));
      final s = LmsService(AuthService(SessionClient(evil), SecureStorage()));
      await expectLater(s.extras.surveys('1'), throwsFormatException);
    });

    test('downloads a topic file, signing in first when xSiTe is signed out', () async {
      signedIn = false;
      final topic = ContentTopic(
          orgUnitId: '213443', id: 977079, title: 'W10', type: 'File', url: '/content/enforced/W10%20Optimisations.pdf');
      final file = await service.extras.topicFile(topic);
      expect(file.name, 'W10 Optimisations.pdf');
      expect(file.type, 'application/pdf');
      expect(utf8.decode(file.bytes), '%PDF-1.7 test');
      expect(asked.first.toString(), '$_le/content/topics/977079/file');
      expect(asked.last.toString(), '$_le/content/topics/977079/file');
      expect(asked.any((u) => u.path == '/d2l/api/lp/1.47/users/whoami'), isTrue);
    });

    test('checklists and surveys together: one tool closed leaves the other', () async {
      final container = ProviderContainer(overrides: [lmsServiceProvider.overrideWithValue(service)]);
      addTearDown(container.dispose);
      final both = await container.read(lmsChecklistsSurveysProvider('213443').future);
      expect(both.summary, '2 checklists · 3 surveys');
      // Course 7 has neither tool for students.
      await expectLater(container.read(lmsChecklistsSurveysProvider('7').future), throwsA(isA<LmsUnavailableException>()));
    });

    test('downloaded files go to a private temporary folder, removed on clear', () async {
      final root = Directory.systemTemp.createTempSync('resit-test-');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/resit-xsite-old').createSync();
      final files = TopicFiles(service.extras, tempRoot: () => root);
      final topic = ContentTopic(orgUnitId: '213443', id: 977079, title: 'W10', type: 'File', url: '/content/W10.pdf');

      final saved = await files.topic(topic);
      expect(saved.name, 'W10 Optimisations.pdf');
      expect(saved.size, 13);
      expect(File(saved.path).readAsStringSync(), '%PDF-1.7 test');
      expect(Directory('${root.path}/resit-xsite-old').existsSync(), isFalse, reason: 'left from an earlier run');
      await files.topic(topic);
      expect(asked.where((u) => u.path.endsWith('/file')), hasLength(1), reason: 'kept for this run');

      await files.clear();
      expect(File(saved.path).existsSync(), isFalse);
      expect(root.listSync(), isEmpty);
    });
  });
}
