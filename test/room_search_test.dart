import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/rbs/booking_service.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:shared_preferences/shared_preferences.dart';

Room _room(String id) =>
    Room(rsrcId: id, rsrcTypId: '1', rsrcName: 'DR $id', rsrcTypName: 'Discussion Room', capacity: 6);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  /// A fake RBS. [answer] decides, per request, which of the asked rooms
  /// come back with a free slot; returning null fails the request.
  ({BookingService service, AuthService auth, List<List<String>> requests, int Function() maxInFlight}) fakeRbs(
      List<String>? Function(List<String> ids) answer) {
    final requests = <List<String>>[];
    var inFlight = 0;
    var maxInFlight = 0;
    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        // Session check: a valid page with a CSRF token.
        return http.Response('<input name="__RequestVerificationToken" value="tok"/>', 200, request: request);
      }
      final list = (jsonDecode(request.bodyFields['parameter']!) as List).first['ResourceList'] as List;
      final ids = [for (final r in list) (r as Map)['RSRC_ID'] as String];
      requests.add(ids);
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inFlight--;
      final back = answer(ids);
      if (back == null) return http.Response('error', 500, request: request);
      return http.Response(
        [for (final id in back) '<div data-rsrcid="$id" data-sltid="s1" data-slotstatus="1">13:00-13:30</div>'].join(),
        200,
        request: request,
      );
    });
    final client = SessionClient(mock);
    final auth = AuthService(client, SecureStorage());
    return (service: BookingService(client, auth), auth: auth, requests: requests, maxInFlight: () => maxInFlight);
  }

  final rooms = [for (var i = 1; i <= 15; i++) _room('r$i')];
  Future<List<RoomCheck>> search(BookingService service) =>
      service.checkEachRoom(rooms, '4 Nov 2026', '07:00', '22:00').toList();

  test('checks rooms 5 per request, a few requests at once', () async {
    final rbs = fakeRbs((ids) => ids);
    final checks = await search(rbs.service);
    rbs.auth.dispose();

    expect(rbs.requests, hasLength(3), reason: '15 rooms in 3 requests instead of 15');
    expect(rbs.requests.every((ids) => ids.length <= 5), isTrue);
    expect(rbs.maxInFlight(), greaterThan(1), reason: 'requests run in parallel');
    expect(rbs.maxInFlight(), lessThanOrEqualTo(6));
    expect(checks, hasLength(15));
    expect(checks.every((c) => c.result != null && c.error == null), isTrue);
  });

  test('a room left out of its batch is checked again on its own', () async {
    // RBS dropping rooms past its cap: only the first 3 of a batch come back.
    final rbs = fakeRbs((ids) => ids.take(3).toList());
    final checks = await search(rbs.service);
    rbs.auth.dispose();

    expect(checks, hasLength(15));
    expect(checks.every((c) => c.result != null), isTrue, reason: 'no free room silently hidden');
    final alone = rbs.requests.where((ids) => ids.length == 1).map((ids) => ids.single).toSet();
    expect(alone, {'r4', 'r5', 'r9', 'r10', 'r14', 'r15'});
  });

  test('a room with no slots is reported as none, after one check alone', () async {
    final rbs = fakeRbs((ids) => ids.where((id) => id != 'r2').toList());
    final checks = await search(rbs.service);
    rbs.auth.dispose();

    final r2 = checks.singleWhere((c) => c.room.rsrcId == 'r2');
    expect(r2.result, isNull);
    expect(r2.error, isNull);
    expect(rbs.requests.where((ids) => ids.length == 1 && ids.single == 'r2'), hasLength(1));
  });

  test('a failing batch falls back to single rooms; a room that keeps failing is reported', () async {
    // Batches containing r7 fail, and so does r7 alone.
    final rbs = fakeRbs((ids) {
      if (ids.contains('r7')) return null;
      return ids;
    });
    final checks = await search(rbs.service);
    rbs.auth.dispose();

    expect(checks, hasLength(15));
    final failed = checks.where((c) => c.error != null).map((c) => c.room.rsrcId).toList();
    expect(failed, ['r7']);
    final batchOfR7 = rbs.requests.where((ids) => ids.length > 1 && ids.contains('r7'));
    expect(batchOfR7, hasLength(2), reason: 'a failed batch is retried once');
    expect(rbs.requests.where((ids) => ids.length == 1 && ids.single == 'r7'), hasLength(2));
    for (final id in ['r6', 'r8', 'r9', 'r10']) {
      expect(checks.singleWhere((c) => c.room.rsrcId == id).result, isNotNull);
    }
  });
}
