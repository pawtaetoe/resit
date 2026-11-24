import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/data/file_opener.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/ui/course_content_screen.dart';
import 'package:resit/features/lms/ui/file_view_screens.dart';
import 'package:resit/features/lms/ui/open_topic.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the device's "open with": notes each file and answers
/// whether an app took it.
class _FakeOpener implements FileOpener {
  final opened = <String>[];
  bool appAvailable = true;

  @override
  Future<bool> open(String path) async {
    opened.add(path);
    return appAvailable;
  }
}

void main() {
  test('PDFs and images are shown in the app, other files go to another app', () {
    expect(viewFor('W10.pdf'), FileView.pdf);
    expect(viewFor('Diagram.PNG'), FileView.image);
    expect(viewFor('photo.jpeg'), FileView.image);
    expect(viewFor('Notes.docx'), FileView.otherApp);
    expect(viewFor('Slides.pptx'), FileView.otherApp);
    expect(viewFor('README.md'), FileView.text);
    expect(viewFor('notes.TXT'), FileView.text);
    expect(viewFor('no-extension'), FileView.otherApp);
  });

  final course = LmsCourse(
    orgUnitId: '213443',
    name: 'INF2004-Embedded Systems Programming [2026/27 T1]',
    code: 'SIT-2610-INF2004',
    semester: '2026/27 Trimester 1',
  );
  final launched = <String>[];

  setUp(() {
    launched.clear();
    // The link opener's platform side: note what was opened.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
      if (call.arguments case {'url': final String url}) launched.add(url);
      return true;
    });
  });

  group('content', () {
    final pdf = ContentTopic(
        orgUnitId: '213443',
        id: 977079,
        title: 'W10 Optimisations',
        type: 'File',
        url: '/content/W10%20Optimisations.pdf',
        unread: true);
    final video = ContentTopic(
        orgUnitId: '213443', id: 977080, title: 'W10 recording', type: 'File', url: '/content/w10.mp4', unread: true);
    final notes = ContentTopic(
        orgUnitId: '213443', id: 977081, title: 'W10 notes', type: 'File', url: '/content/notes.docx', unread: true);
    final readme = ContentTopic(
        orgUnitId: '213443', id: 977082, title: 'Lab setup', type: 'File', url: '/content/README.md', unread: true);
    final modules = [
      ContentModule(id: 1, title: 'Lecture', topics: [pdf, video, notes, readme])
    ];

    late List<Uri> fileRequests;
    late Directory root;
    late LmsService service;
    late _FakeOpener opener;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      fileRequests = [];
      opener = _FakeOpener();
      root = Directory.systemTemp.createTempSync('resit-test-');
      service = LmsService(AuthService(SessionClient(MockClient((r) async {
        fileRequests.add(r.url);
        final (name, type, body) = switch (r.url.path) {
          final p when p.contains('/977081/') => ('Notes.docx', 'application/octet-stream', 'DOCX'),
          final p when p.contains('/977082/') => ('README.md', 'text/markdown', '# Lab setup\nFlash the Pico W first.'),
          _ => ('W10.pdf', 'application/pdf', '%PDF'),
        };
        return http.Response.bytes(utf8.encode(body), 200,
            headers: {'content-type': type, 'content-disposition': 'attachment; filename="$name"'}, request: r);
      })), SecureStorage()));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> pump(WidgetTester tester, {required bool desktop}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          lmsContentsProvider('213443').overrideWith((ref) async => modules),
          lmsProgressProvider('213443').overrideWith((ref) async => CourseProgress([])),
          lmsOverviewProvider('213443').overrideWith(
              (ref) async => CourseOverview(text: 'Welcome to INF2004. Read the syllabus.', hasAttachment: true)),
          opensFilesHereProvider.overrideWithValue(desktop),
          topicFilesProvider.overrideWithValue(TopicFiles(service.extras, tempRoot: () => root)),
          fileOpenerProvider.overrideWithValue(opener),
          // The PDF engine isn't available to widget tests.
          pdfViewBuilderProvider.overrideWithValue((path) => Text('PDF view of ${path.split('/').last}')),
        ],
        child: MaterialApp(home: CourseContentScreen(course: course)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the course overview and each file\'s type', (tester) async {
      await pump(tester, desktop: false);
      expect(find.text('Course overview'), findsOneWidget);
      expect(find.text('Welcome to INF2004. Read the syllabus.'), findsOneWidget);
      expect(find.text('Open attachment'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
    });

    testWidgets('where files can\'t be opened here (web), a PDF opens on xSiTe without downloading', (tester) async {
      await pump(tester, desktop: false);
      await tester.tap(find.text('W10 Optimisations'));
      await tester.pumpAndSettle();
      expect(fileRequests, isEmpty);
      expect(launched, ['https://xsite.singaporetech.edu.sg/d2l/le/content/213443/viewContent/977079/View']);
    });

    Future<void> tapAndWait(WidgetTester tester, String title, bool Function() done) async {
      await tester.scrollUntilVisible(find.text(title), 100);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(title));
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        // Let the rest of the open (after the file lands) finish.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('a PDF is downloaded from xSiTe and shown in the app; a video opens on xSiTe', (tester) async {
      await pump(tester, desktop: true);
      await tapAndWait(
          tester, 'W10 Optimisations', () => root.listSync(recursive: true).any((f) => f.path.endsWith('W10.pdf')));
      expect(fileRequests.map((u) => u.toString()),
          ['https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/213443/content/topics/977079/file']);
      expect(find.byType(FileViewScreen), findsOneWidget);
      expect(find.text('PDF view of W10.pdf'), findsOneWidget);
      expect(find.text('W10.pdf'), findsOneWidget);
      expect(launched, isEmpty, reason: 'not sent to the browser');
      expect(opener.opened, isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('W10 recording'));
      await tester.pumpAndSettle();
      expect(fileRequests, hasLength(1), reason: 'videos are not downloaded');
      expect(launched.single, contains('/viewContent/977080/View'));
    });

    testWidgets('a Word file goes to another app on the device', (tester) async {
      await pump(tester, desktop: true);
      await tapAndWait(tester, 'W10 notes', () => opener.opened.isNotEmpty);
      expect(opener.opened.single, endsWith('/213443-977081/Notes.docx'));
      expect(find.text('Opened Notes.docx (4 bytes)'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a text file is shown in the app', (tester) async {
      await pump(tester, desktop: true);
      await tester.scrollUntilVisible(find.text('Lab setup'), 100);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Lab setup'));
        for (var i = 0; i < 100 && !root.listSync(recursive: true).any((f) => f.path.endsWith('README.md')); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      // The page opens, then reads the file from disk (real I/O).
      // Each step of the read waits on the disk, then on a frame.
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 50 && find.byType(SelectionArea).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(FileViewScreen), findsOneWidget);
      expect(find.text('# Lab setup\nFlash the Pico W first.'), findsOneWidget);
      expect(opener.opened, isEmpty);
      expect(launched, isEmpty);
    });

    testWidgets('with no app for the file, it opens on xSiTe instead', (tester) async {
      opener.appAvailable = false;
      await pump(tester, desktop: true);
      await tapAndWait(tester, 'W10 notes', () => launched.isNotEmpty);
      expect(opener.opened, hasLength(1));
      expect(launched.single, contains('/viewContent/977081/View'));
    });
  });
}
