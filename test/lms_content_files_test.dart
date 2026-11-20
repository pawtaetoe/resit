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
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/ui/course_content_screen.dart';
import 'package:resit/features/lms/ui/open_topic.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
    final modules = [
      ContentModule(id: 1, title: 'Lecture', topics: [pdf, video])
    ];

    late List<Uri> fileRequests;
    late Directory root;
    late LmsService service;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      fileRequests = [];
      root = Directory.systemTemp.createTempSync('resit-test-');
      service = LmsService(AuthService(SessionClient(MockClient((r) async {
        fileRequests.add(r.url);
        return http.Response.bytes(utf8.encode('%PDF'), 200,
            headers: {'content-type': 'application/pdf', 'content-disposition': 'attachment; filename="W10.pdf"'},
            request: r);
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

    testWidgets('on a phone, a PDF opens on xSiTe without downloading', (tester) async {
      await pump(tester, desktop: false);
      await tester.tap(find.text('W10 Optimisations'));
      await tester.pumpAndSettle();
      expect(fileRequests, isEmpty);
      expect(launched, ['https://xsite.singaporetech.edu.sg/d2l/le/content/213443/viewContent/977079/View']);
    });

    testWidgets('on a computer, a PDF is downloaded from xSiTe to open it there; a video is not', (tester) async {
      await pump(tester, desktop: true);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('W10 Optimisations'));
        for (var i = 0; i < 100 && launched.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(fileRequests.map((u) => u.toString()),
          ['https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/213443/content/topics/977079/file']);
      expect(launched.single, startsWith('file://'));
      expect(launched.single, endsWith('/213443-977079/W10.pdf'));
      expect(find.text('Opened W10.pdf (4 bytes)'), findsOneWidget);
      await tester.tap(find.text('W10 recording'));
      await tester.pumpAndSettle();
      expect(fileRequests, hasLength(1));
    });
  });
}
