import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/common/data/private_store.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';
import 'package:resit/features/timetable/data/timetable_store.dart';
import 'package:resit/features/timetable/presentation/timetable_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

ClassSession _class(DateTime date, String code) => ClassSession(
      date: date,
      courseCode: code,
      section: 'L1',
      component: 'Lecture',
      startMin: 9 * 60,
      endMin: 11 * 60,
      location: 'E2-03-01',
      coinciding: false,
    );

/// Sign-in that can't reach SIT.
class _UnreachableSession extends SessionController {
  int attempts = 0;

  _UnreachableSession()
      : super(AuthService(SessionClient(), SecureStorage()), SecureStorage(), watchLifecycle: false) {
    state = const SessionState(phase: SessionPhase.failed, error: 'SIT took too long to respond.');
  }

  @override
  Future<bool> ensureSignedIn({bool force = false}) async {
    attempts++;
    return false;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('TimetableWeekStore', () {
    test('keeps weeks between launches, encrypted store round trip', () async {
      final now = DateTime(2026, 11, 18, 10);
      final monday = _mondayOf(now);
      await TimetableWeekStore(now: () => now).save(WeekSchedule(monday, [_class(monday, 'CSC 2101')]));

      final saved = await TimetableWeekStore(now: () => now).load();
      expect(saved.keys, [monday]);
      expect(saved[monday]!.week.sessions.single.courseCode, 'CSC 2101');
      expect(saved[monday]!.fetchedAt, now);
    });

    test('drops weeks long past and keeps at most maxWeeks', () async {
      var now = DateTime(2026, 11, 18, 10);
      final store = TimetableWeekStore(now: () => now);
      final thisMonday = _mondayOf(now);
      await store.save(WeekSchedule(thisMonday.subtract(const Duration(days: 28)), const []));
      for (var i = 0; i < TimetableWeekStore.maxWeeks + 2; i++) {
        now = now.add(const Duration(minutes: 1));
        await store.save(WeekSchedule(DateTime(thisMonday.year, thisMonday.month, thisMonday.day + 7 * i), const []));
      }
      final saved = await store.load();
      expect(saved.length, TimetableWeekStore.maxWeeks);
      expect(saved.containsKey(thisMonday.subtract(const Duration(days: 28))), isFalse);
      // The two read longest ago went first.
      expect(saved.containsKey(thisMonday), isFalse);
      expect(saved.containsKey(DateTime(thisMonday.year, thisMonday.month, thisMonday.day + 7 * (TimetableWeekStore.maxWeeks + 1))), isTrue);
    });

    test('saves started together both land', () async {
      final now = DateTime(2026, 11, 18, 10);
      final store = TimetableWeekStore(now: () => now);
      final monday = _mondayOf(now);
      await Future.wait([
        store.save(WeekSchedule(monday, const [])),
        store.save(WeekSchedule(monday.add(const Duration(days: 7)), const [])),
      ]);
      expect((await store.load()).length, 2);
    });

    test('clear erases everything', () async {
      final store = TimetableWeekStore();
      await store.save(WeekSchedule(_mondayOf(DateTime.now()), const []));
      await store.clear();
      expect(await store.load(), isEmpty);
      expect(await PrivateStore().read('timetable_weeks'), isNull);
    });
  });

  testWidgets('shows the saved week when SIT cannot be reached', (tester) async {
    final monday = _mondayOf(DateTime.now());
    await TimetableWeekStore().save(WeekSchedule(monday, [_class(monday, 'INF 2004')]));
    final session = _UnreachableSession();

    await tester.pumpWidget(ProviderScope(
      overrides: [sessionControllerProvider.overrideWith((ref) => session)],
      child: const MaterialApp(home: TimetableScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saved timetable'), findsOneWidget);
    expect(find.textContaining("Couldn't reach SIT."), findsOneWidget);
    expect(find.textContaining('INF 2004'), findsWidgets);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(session.attempts, greaterThanOrEqualTo(1));
  });

  testWidgets('a week with no saved copy says so instead of failing', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionControllerProvider.overrideWith((ref) => _UnreachableSession())],
      child: const MaterialApp(home: TimetableScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reach SIT"), findsOneWidget);
    expect(find.textContaining('no saved copy of this week'), findsOneWidget);
  });
}
