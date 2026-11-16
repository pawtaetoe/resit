import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/in4sit/timetable_service.dart';
import 'package:resit/features/timetable/data/upcoming_classes.dart';
import 'package:shared_preferences/shared_preferences.dart';

ClassSession _s(DateTime day, int start, int end, [String code = 'CSC 2101']) => ClassSession(
      date: day,
      courseCode: code,
      section: 'L1',
      component: 'Lecture',
      startMin: start,
      endMin: end,
      location: 'E2-03-01',
      coinciding: false,
    );

/// A timetable that answers from [weeks] (by Monday), or fails when [down].
class _FakeTimetable extends TimetableService {
  final Map<DateTime, List<ClassSession>> weeks;
  bool down = false;
  var calls = 0;

  _FakeTimetable(this.weeks) : super(AuthService(SessionClient(), SecureStorage()));

  @override
  Future<WeekSchedule> week(DateTime monday, {void Function(MfaChallenge challenge)? onMfaChallenge}) async {
    calls++;
    if (down) throw Exception('offline');
    return WeekSchedule(monday, weeks[monday] ?? const []);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mon = DateTime(2026, 11, 2);
  final tue = DateTime(2026, 11, 3);
  final classes = [
    _s(tue, 14 * 60, 16 * 60, 'B'),
    _s(mon, 9 * 60, 11 * 60, 'A'),
    _s(tue, 9 * 60, 11 * 60, 'C'),
  ];

  test('during a class: that class, and the next one to start', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 2, 10));
    expect(r.current?.courseCode, 'A');
    expect(r.next?.courseCode, 'C');
  });

  test('between classes: no current, the next one whatever the list order', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 2, 11));
    expect(r.current, isNull);
    expect(r.next?.courseCode, 'C');
    expect(currentAndNextClass(classes, DateTime(2026, 11, 3, 12)).next?.courseCode, 'B');
  });

  test('in the last class: no next one', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 3, 15));
    expect(r.current?.courseCode, 'B');
    expect(r.next, isNull);
  });

  test('nothing once every class has ended', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 3, 16));
    expect(r.current, isNull);
    expect(r.next, isNull);
    expect(currentAndNextClass(const [], mon).next, isNull);
  });

  test('saved copies round-trip', () {
    final back = classSessionFromJson(classes.first.toJson());
    expect(back.start, DateTime(2026, 11, 3, 14));
    expect(back.end, DateTime(2026, 11, 3, 16));
    expect(back.courseCode, 'B');
    expect(back.location, 'E2-03-01');
  });

  group('load', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('offline, the saved copy is used without the classes that have ended', () async {
      var now = DateTime(2026, 11, 2, 8);
      final timetable = _FakeTimetable({
        mon: [_s(mon, 9 * 60, 11 * 60, 'A'), _s(tue, 9 * 60, 11 * 60, 'B')],
      });
      final service = UpcomingClassesService(timetable, now: () => now);
      expect((await service.load()).map((s) => s.courseCode), ['A', 'B']);

      timetable.down = true;
      now = DateTime(2026, 11, 3, 10); // A is over, B is on
      expect((await service.load(force: true)).map((s) => s.courseCode), ['B']);
      now = DateTime(2026, 11, 3, 12); // all over
      expect(await service.load(force: true), isEmpty, reason: 'never a list whose classes are all over');
    });

    test('a copy read within the hour with a class to come is used as is', () async {
      var now = DateTime(2026, 11, 2, 8);
      final timetable = _FakeTimetable({
        mon: [_s(mon, 9 * 60, 11 * 60, 'A'), _s(tue, 9 * 60, 11 * 60, 'B')],
      });
      final service = UpcomingClassesService(timetable, now: () => now);
      await service.load();
      expect(timetable.calls, 1);

      now = DateTime(2026, 11, 2, 8, 50);
      expect((await service.load()).map((s) => s.courseCode), ['A', 'B']);
      expect(timetable.calls, 1, reason: 'fresh enough');

      await service.load(force: true);
      expect(timetable.calls, 2, reason: 'pull to refresh');

      now = DateTime(2026, 11, 2, 10, 30); // over an hour later
      await service.load();
      expect(timetable.calls, 3);
    });

    test('a fresh copy whose classes have all started is read again', () async {
      var now = DateTime(2026, 11, 2, 8);
      final timetable = _FakeTimetable({
        mon: [_s(mon, 9 * 60, 11 * 60, 'A')],
      });
      final service = UpcomingClassesService(timetable, now: () => now);
      await service.load();
      final before = timetable.calls;
      now = DateTime(2026, 11, 2, 9, 30);
      await service.load();
      expect(timetable.calls, greaterThan(before));
    });

    test('a copy saved by an older version (plain list, in preferences) still loads, then moves', () async {
      SharedPreferences.setMockInitialValues({
        'upcoming_classes': jsonEncode([_s(tue, 9 * 60, 11 * 60, 'B').toJson()]),
      });
      final timetable = _FakeTimetable({})..down = true;
      final service = UpcomingClassesService(timetable, now: () => DateTime(2026, 11, 3, 8));
      expect((await service.saved()).single.courseCode, 'B');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('upcoming_classes'), isNull, reason: 'moved to secure storage');
      // No fetch time recorded: in4SIT is asked (and is down), so the copy is used.
      expect((await service.load()).single.courseCode, 'B');
      expect(timetable.calls, 1);
    });
  });
}
