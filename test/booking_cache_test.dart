import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/rbs/booking_service.dart';
import 'package:resit/sites/rbs/rbs_parsers.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Map<String, int> fetches;
  late List<Map<String, String>> cancels;
  late List<Map<String, String>> encrypts;
  late int sessionChecks;
  late List<List<String>> current;
  late BookingService service;
  late DateTime now;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    fetches = {};
    cancels = [];
    encrypts = [];
    sessionChecks = 0;
    now = DateTime(2026, 11, 7, 9);
    current = [
      ['DR 1', '9 Nov 2026', '10:00-12:00', '', 'proj', 'Confirmed', 'B1', 'c1'],
    ];
    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        sessionChecks++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response('<input name="__RequestVerificationToken" value="tok"/>', 200, request: request);
      }
      final path = request.url.path;
      if (path == '/DHB001/GetDashBoardDataByStatus') {
        final status = request.bodyFields['bookingStatus']!;
        fetches[status] = (fetches[status] ?? 0) + 1;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response(jsonEncode({'data': status == 'current' ? current : []}), 200, request: request);
      }
      if (path == '/common/EncryptDecryptFunc') {
        encrypts.add(request.bodyFields);
        // RBS answers with the encrypted ID as text, ending in a newline.
        return http.Response('enc/${request.bodyFields['_encryptData']}+=\n', 200,
            request: request, headers: {'content-type': 'text/html; charset=utf-8'});
      }
      if (path == '/DHB001/SaveToCancel') {
        cancels.add(request.bodyFields);
        current = [];
        // RBS's own answer: the JSON string "1".
        return http.Response('"1"', 200, request: request, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('nf', 404, request: request);
    });
    final client = SessionClient(mock);
    service = BookingService(client, AuthService(client, SecureStorage()), now: () => now);
  });

  test('screens asking for current bookings together share one request', () async {
    // My bookings, the quota card and Home's next booking, all at once.
    final results = await Future.wait([
      service.getBookings(bookingStatus: 'current'),
      service.getQuotaBookings(),
      service.getBookings(),
    ]);
    expect(results.every((r) => r.length == 1), isTrue);
    expect(fetches, {'current': 1, 'history': 1});
    expect(sessionChecks, 1, reason: 'one session check for the token, shared');

    await service.getBookings();
    expect(fetches['current'], 1, reason: 'reused within 30 s');
    now = now.add(const Duration(seconds: 31));
    await service.getBookings();
    expect(fetches['current'], 2);
    await service.getBookings(force: true);
    expect(fetches['current'], 3);
  });

  test('cancelling forgets the kept bookings', () async {
    expect(await service.getBookings(), hasLength(1));
    await service.cancelBooking('c1');
    expect(await service.getBookings(), isEmpty);
    expect(fetches['current'], 2);
  });

  test("cancelling sends what RBS's own Cancel button sends", () async {
    await service.cancelBooking('20261117BKG000020');
    // First RBS encrypts the booking reference...
    expect(encrypts, [
      {'_isEncrypt': 'true', '_encryptData': '20261117BKG000020', '_decryptData': '', '__RequestVerificationToken': 'tok'},
    ]);
    // ...then the encrypted ID is cancelled.
    expect(cancels, [
      {'__RequestVerificationToken': 'tok', 'bookID[]': 'enc/20261117BKG000020+=', 'reason': 'No longer needed'},
    ]);
  });

  test('an encryption answer that is not an ID stops the cancellation', () {
    expect(encryptedIdFrom('lrxZzsWkbMGeD84xqY/Jj6Od+5==\n'), 'lrxZzsWkbMGeD84xqY/Jj6Od+5==');
    expect(encryptedIdFrom('<html>Error</html>'), isNull);
    expect(encryptedIdFrom('  '), isNull);
  });

  test('only "1" counts as a confirmed cancellation', () {
    expect(cancelSucceeded('"1"'), isTrue);
    expect(cancelSucceeded('1'), isTrue);
    expect(cancelSucceeded('"0"'), isFalse);
    expect(cancelSucceeded('<html>error</html>'), isFalse);
  });

  test('the weekly quota is worked out once per week for the same bookings', () {
    final bookings = [
      Booking(
          roomName: 'DR 1',
          date: '4 Nov 2026',
          timeRange: '10:00-12:00',
          academicText: '',
          purpose: '',
          status: 'Confirmed',
          bookingRef: 'B1',
          cancelId: ''),
    ];
    final types = {'dr 1': discussionRoom};
    final a = WeeklyQuota.from(bookings, DateTime(2026, 11, 4), types);
    final b = WeeklyQuota.from(bookings, DateTime(2026, 11, 6), types);
    expect(identical(a, b), isTrue);
    expect(a.used(discussionRoom), 120);
    // New data (a new list) is counted afresh.
    final c = WeeklyQuota.from([...bookings, ...bookings.map((x) => x)], DateTime(2026, 11, 4), types);
    expect(identical(a, c), isFalse);
    expect(c.used(discussionRoom), 120, reason: 'same booking ref counted once');
  });
}
