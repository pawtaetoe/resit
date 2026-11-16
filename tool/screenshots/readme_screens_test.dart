// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders the README screenshots from the real screens with demo data
// (no real student data, no network). Not part of the test suite.
//
//   flutter test tool/screenshots/readme_screens_test.dart --update-goldens
//
// Writes PNGs to docs/screenshots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/calendar/data/academic_calendar.dart';
import 'package:resit/features/exams/data/academic_record.dart';
import 'package:resit/features/exams/presentation/academic_progress_screen.dart';
import 'package:resit/features/lms/data/lms_activities.dart';
import 'package:resit/features/lms/data/lms_service.dart';
import 'package:resit/features/lms/presentation/course_sections.dart';
import 'package:resit/features/lms/presentation/courses_screen.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';
import 'package:resit/features/timetable/presentation/timetable_screen.dart';
import 'package:resit/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _sdk = Platform.environment['FLUTTER_ROOT'] ?? '/home/user/sdk/flutter';

Future<void> _loadFonts() async {
  final dir = '$_sdk/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => ByteData.view(File('$dir/$f').readAsBytesSync().buffer);
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(read('Roboto-$w.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'))).load();
}

final _now = DateTime.now();
final _today = DateTime(_now.year, _now.month, _now.day);
final _monday = DateTime(_today.year, _today.month, _today.day - (_today.weekday - 1));

ClassSession _class(int day, String code, String kind, int start, int end, String room, {String section = 'L1'}) =>
    ClassSession(
      date: DateTime(_monday.year, _monday.month, _monday.day + day),
      courseCode: code,
      section: section,
      component: kind,
      startMin: start * 60,
      endMin: end * 60,
      location: room,
      coinciding: false,
    );

final _week = [
  _class(0, 'CSC 2101', 'Lectorial', 9, 11, 'Online'),
  _class(0, 'INF 2004', 'Lecture', 11, 13, 'E2-03-01'),
  _class(1, 'CSC 3104', 'Tutorial', 13, 15, 'E2-01-01', section: 'T1'),
  _class(2, 'INF 2004', 'Laboratory', 11, 13, 'E2-05-14', section: 'P3'),
  _class(3, 'INF 2002', 'Laboratory', 11, 13, 'E2-07-14', section: 'P2'),
  _class(4, 'CSC 3104', 'Laboratory', 10, 11, 'E6-2M-02', section: 'P2'),
  _class(4, 'CSC 2101', 'Tutorial', 14, 16, 'Online', section: 'T2'),
];

/// Today's and tomorrow's classes, for Home's "Up next".
List<ClassSession> get _upcoming {
  final h = _now.hour;
  ClassSession at(DateTime d, String code, String kind, int s, int e, String room) => ClassSession(
      date: d, courseCode: code, section: 'L1', component: kind, startMin: s * 60, endMin: e * 60, location: room, coinciding: false);
  final nowStart = h.clamp(1, 21);
  return [
    at(_today, 'INF 2004', 'Lecture', nowStart, nowStart + 2, 'E2-03-01'),
    at(_today.add(const Duration(days: 1)), 'CSC 2101', 'Lectorial', 9, 11, 'Online'),
  ];
}

final _booking = Booking(
  roomName: 'DR 2-04 (6 pax)',
  date: '${_today.add(const Duration(days: 2)).day} ${const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][_today.add(const Duration(days: 2)).month]} ${_today.add(const Duration(days: 2)).year}',
  timeRange: '14:00-16:00',
  academicText: '',
  purpose: 'Group project',
  status: 'Confirmed',
  bookingRef: 'B000123',
  cancelId: '1',
);

final _record = AcademicRecord(
  creditsEarned: 72,
  creditsInProgress: 30,
  coursesPassed: 12,
  cumulativeGpa: '4.12',
  latestTermGpa: '4.30',
  admitTerm: 'AY 2024/25 Trimester 1',
  fetchedAt: _now,
  terms: const [
    TermSummary(label: 'T1 24/25', name: 'AY 2024/25 Trimester 1', termGpa: 3.9, cumulativeGpa: 3.9, creditsEarned: 18),
    TermSummary(label: 'T2 24/25', name: 'AY 2024/25 Trimester 2', termGpa: 4.1, cumulativeGpa: 4.0, creditsEarned: 18),
    TermSummary(label: 'T3 24/25', name: 'AY 2024/25 Trimester 3', termGpa: 4.2, cumulativeGpa: 4.07, creditsEarned: 18),
    TermSummary(label: 'T1 25/26', name: 'AY 2025/26 Trimester 1', termGpa: 4.3, cumulativeGpa: 4.12, creditsEarned: 18),
  ],
  gradeCounts: const {'A': 5, 'A-': 4, 'B+': 2, 'B': 1},
);

LmsCourse _course(String id, String code, String title, int daysAgo) => LmsCourse(
      orgUnitId: id,
      name: '$code-$title [2026/27 T1]',
      code: 'SIT-2610-$code',
      semester: '2026/27 Trimester 1',
      start: DateTime(2026, 8, 24),
      lastAccessed: _now.subtract(Duration(days: daysAgo)),
    );

final _courses = [
  _course('1', 'INF2004', 'Embedded Systems Programming', 0),
  _course('2', 'CSC2101', 'Professional Software Development and Team Project 1', 1),
  _course('3', 'CSC3104', 'Cloud and Distributed Computing', 2),
  _course('4', 'INF2002', 'Human Computer Interaction', 3),
];

ContentItem _item(String ou, int id, bool done) =>
    ContentItem(orgUnitId: ou, objectId: id, title: 'Item $id', required: 1, completed: done ? 1 : 0);

CourseProgress _progress(String ou, int done, int total) =>
    CourseProgress([for (var i = 0; i < total; i++) _item(ou, i, i < done)]);

final _announcements = {
  '1': [
    Announcement(
        id: '1',
        title: 'Week 11 lab moved to E2-05-14',
        body: 'This week\'s lab is in E2-05-14. Bring your Pico and the sensor kit.',
        date: _today.add(const Duration(hours: 8, minutes: 30))),
    Announcement(id: '2', title: 'Project write-up template', body: 'The template is in Content.', date: _today.subtract(const Duration(days: 4)).add(const Duration(hours: 10))),
  ],
  '2': [
    Announcement(
        id: '3',
        title: 'Sprint review slots released',
        body: 'Book a 15-minute slot for your team in the sign-up sheet.',
        date: _today.subtract(const Duration(days: 1)).add(const Duration(hours: 16, minutes: 45))),
  ],
  '3': [
    Announcement(id: '4', title: 'Quiz 3 opens on Friday', body: 'Covers containers and orchestration.', date: _today.subtract(const Duration(days: 2)).add(const Duration(hours: 9, minutes: 15))),
  ],
  '4': <Announcement>[],
};

final _assignments = {
  '1': [
    Assignment(orgUnitId: '1', id: 11, name: 'Lab 3 report', dueDate: _today.add(const Duration(days: 2, hours: 23, minutes: 59)), outOf: 20),
    Assignment(orgUnitId: '1', id: 12, name: 'Lab 2 report', dueDate: _today.subtract(const Duration(days: 9)), submissions: [_now.subtract(const Duration(days: 10))]),
  ],
  '2': [Assignment(orgUnitId: '2', id: 21, name: 'Sprint 2 retrospective', dueDate: _today.add(const Duration(days: 1, hours: 12)), isGroup: true)],
  '3': <Assignment>[],
  '4': <Assignment>[],
};

final _quizzes = {
  '1': <Quiz>[],
  '2': <Quiz>[],
  '3': [Quiz(orgUnitId: '3', id: 31, name: 'Quiz 3: Orchestration', dueDate: _today.add(const Duration(days: 5, hours: 18)), attemptsAllowed: 1, timeLimit: 30)],
  '4': <Quiz>[],
};

class _FakeTimetable extends TimetableService {
  _FakeTimetable() : super(AuthService(SessionClient(), SecureStorage()));

  @override
  Future<WeekSchedule> week(DateTime monday, {void Function(MfaChallenge)? onMfaChallenge}) async =>
      WeekSchedule(monday, monday == _monday ? _week : const []);

  @override
  void reset() {}
}

class _FakeLms extends LmsService {
  _FakeLms() : super(AuthService(SessionClient(), SecureStorage()));

  @override
  Future<List<LmsCourse>> courses({void Function(MfaChallenge)? onMfaChallenge, bool force = false}) async => _courses;
}

late AcademicCalendar _calendar;

List<Override> _overrides() => [
      authStateProvider.overrideWith((ref) => true),
      academicCalendarProvider.overrideWith((ref) async => _calendar),
      upcomingClassesProvider.overrideWith((ref) async => _upcoming),
      savedUpcomingClassesProvider.overrideWith((ref) async => _upcoming),
      upcomingClassesUpdatedProvider.overrideWith((ref) async => _now.subtract(const Duration(minutes: 20))),
      nextBookingProvider.overrideWith((ref) async => _booking),
      academicRecordProvider.overrideWith((ref) async => _record),
      savedAcademicRecordProvider.overrideWith((ref) async => _record),
      graduationYearProvider.overrideWith((ref) async => 2028),
      timetableServiceProvider.overrideWith((ref) => _FakeTimetable()),
      lmsServiceProvider.overrideWith((ref) => _FakeLms()),
      lmsProgressProvider.overrideWith((ref, id) async => _progress(id, {'1': 46, '2': 30, '3': 12, '4': 20}[id]!, {'1': 61, '2': 40, '3': 35, '4': 28}[id]!)),
      lmsAnnouncementsProvider.overrideWith((ref, id) async => _announcements[id]!),
      lmsAssignmentsProvider.overrideWith((ref, id) async => _assignments[id]!),
      lmsQuizzesProvider.overrideWith((ref, id) async => _quizzes[id]!),
      lmsGradesProvider.overrideWith((ref, id) async => CourseGrades([])),
      lmsGroupsProvider.overrideWith((ref, id) async => [MyGroup(category: 'Project Groups', name: 'Team 7', memberCount: 5)]),
    ];

Future<void> _shoot(WidgetTester tester, Widget app, String name, {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(ProviderScope(overrides: _overrides(), child: app));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../docs/screenshots/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Widget _screen(Widget home, {Brightness brightness = Brightness.light}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: home,
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
    _calendar = AcademicCalendar(
        parseAcademicCalendar(File('test/fixtures/sit_academic_calendar.html').readAsStringSync()), _now);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'rbs_username': '2100000', 'rbs_password': 'demo'});
  });

  testWidgets('home', (t) => _shoot(t, const ReSitApp(), 'home'));
  testWidgets('home dark', (t) => _shoot(t, const ReSitApp(), 'home_dark', brightness: Brightness.dark));
  testWidgets('timetable', (t) => _shoot(t, _screen(const TimetableScreen()), 'timetable'));
  testWidgets('courses', (t) => _shoot(t, _screen(const CoursesScreen()), 'xsite_courses'));
  testWidgets('course', (t) => _shoot(t, _screen(CourseScreen(course: _courses.first)), 'xsite_course'));
  testWidgets('progress', (t) => _shoot(t, _screen(const AcademicProgressScreen()), 'academic_progress'));
}
