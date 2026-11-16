import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/features/timetable/timetable_providers.dart';
import 'package:resit/features/timetable/ui/timetable_view_model.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/timetable_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// in4SIT's timetable, answering from [failing] with an error and every
/// other week with one class.
class _FakeTimetable extends TimetableService {
  final Set<DateTime> failing;
  final List<DateTime> asked = [];

  _FakeTimetable({this.failing = const {}}) : super(AuthService(SessionClient(), SecureStorage()));

  @override
  Future<WeekSchedule> week(DateTime monday, {void Function(MfaChallenge)? onMfaChallenge}) async {
    asked.add(monday);
    if (failing.contains(monday)) throw Exception('in4SIT is down');
    return WeekSchedule(monday, [
      ClassSession(
        date: monday,
        courseCode: 'CSC 2101',
        section: 'L1',
        component: 'Lecture',
        startMin: 9 * 60,
        endMin: 11 * 60,
        location: 'E2-03-01',
        coinciding: false,
      ),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final monday = DateTime(2026, 10, 5);
  final next = DateTime(2026, 10, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// A view model reading from [service], kept alive for the test, and a
  /// way to read its state.
  (TimetableViewModel, TimetableState Function()) viewModel(TimetableService service, {bool signedIn = true}) {
    final container = ProviderContainer(overrides: [
      timetableServiceProvider.overrideWithValue(service),
      authStateProvider.overrideWith((ref) => signedIn),
    ]);
    addTearDown(container.dispose);
    container.listen(timetableViewModelProvider, (_, __) {});
    return (container.read(timetableViewModelProvider.notifier), () => container.read(timetableViewModelProvider));
  }

  test('reads a week, keeps a copy, and reads the next week behind it', () async {
    final service = _FakeTimetable();
    final (vm, state) = viewModel(service);

    await vm.loadWeek(monday);
    await pumpEventQueue();

    expect(service.asked, [monday, next]);
    expect(state().weekOf(monday).live?.sessions, hasLength(1));
    expect(state().weekOf(next).live, isNotNull);
    expect(state().saved.keys, containsAll([monday, next]));
    expect(state().loading, isEmpty);
    expect(state().colours.keys, ['CSC2101']);
  });

  test('a week read already is not asked for again until refreshed', () async {
    final service = _FakeTimetable();
    final (vm, _) = viewModel(service);
    await vm.loadWeek(monday);
    await pumpEventQueue();
    service.asked.clear();

    await vm.loadWeek(monday);
    expect(service.asked, isEmpty);

    await vm.refresh(monday);
    expect(service.asked.first, monday);
  });

  test("keeps a week's error, but not a look-ahead's", () async {
    final service = _FakeTimetable(failing: {next});
    final (vm, state) = viewModel(service);

    await vm.loadWeek(monday);
    await pumpEventQueue();
    expect(service.asked, [monday, next]);
    expect(state().weekOf(next).error, isNull, reason: 'asked for again when shown');

    await vm.loadWeek(next);
    expect(state().weekOf(next).error, isNotNull);
  });

  test('reads nothing while signed out', () async {
    final service = _FakeTimetable();
    final (vm, state) = viewModel(service, signedIn: false);

    await vm.loadWeek(monday);
    expect(service.asked, isEmpty);
    expect(state().weekOf(monday).loading, isFalse);
  });
}
