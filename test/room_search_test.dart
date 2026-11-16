import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/rbs/booking_service.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Room _room(String id) =>
    Room(rsrcId: id, rsrcTypId: '1', rsrcName: 'DR $id', rsrcTypName: 'Discussion Room', capacity: 6);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('checks each room in its own request, a few at once, retrying failures once', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final attempts = <String, int>{};
    final roomsPerRequest = <int>[];

    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        // Session check: a valid page with a CSRF token.
        return http.Response('<input name="__RequestVerificationToken" value="tok"/>', 200, request: request);
      }
      final list = (jsonDecode(request.bodyFields['parameter']!) as List).first['ResourceList'] as List;
      roomsPerRequest.add(list.length);
      final id = list.single['RSRC_ID'] as String;
      attempts[id] = (attempts[id] ?? 0) + 1;

      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inFlight--;

      // r3 fails once then works; r7 always fails.
      if ((id == 'r3' && attempts[id] == 1) || id == 'r7') return http.Response('error', 500, request: request);
      return http.Response(
        '<div data-rsrcid="$id" data-sltid="s1" data-slotstatus="1">13:00-13:30</div>',
        200,
        request: request,
      );
    });

    final client = SessionClient(mock);
    final auth = AuthService(client, SecureStorage());
    final service = BookingService(client, auth);
    final rooms = [for (var i = 1; i <= 15; i++) _room('r$i')];

    final checks = await service.checkEachRoom(rooms, '4 Nov 2026', '07:00', '22:00').toList();
    auth.dispose();

    expect(roomsPerRequest.every((n) => n == 1), isTrue, reason: 'one room per request');
    expect(maxInFlight, lessThanOrEqualTo(6));
    expect(maxInFlight, greaterThan(1), reason: 'requests run in parallel');
    expect(checks, hasLength(15));
    expect(attempts['r3'], 2);
    expect(checks.firstWhere((c) => c.room.rsrcId == 'r3').result, isNotNull);
    final failed = checks.where((c) => c.error != null).map((c) => c.room.rsrcId).toList();
    expect(failed, ['r7']);
    expect(attempts['r7'], 2);
  });
}
