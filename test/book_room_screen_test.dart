import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';
import 'package:resit/features/room_booking/ui/dashboard_screen.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/rbs/booking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every half hour of the day, free, for room [id].
String _freeDay(String id) => [
      for (var m = bookingOpenMin; m < bookingCloseMin; m += 30)
        '<div data-rsrcid="$id" data-sltid="s$m" data-slotstatus="1">${hhmm(m)}-${hhmm(m + 30)}</div>',
    ].join();

/// Lets the fake server answer (real async) and the screen redraw.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  late List<String> posts;
  late AuthService auth;
  late BookingService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    posts = [];
    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response('<input name="__RequestVerificationToken" value="tok"/>', 200, request: request);
      }
      final path = request.url.path;
      posts.add(path);
      switch (path) {
        case '/SRB001/SearchSRB001List':
          return http.Response(
              jsonEncode([
                {'RSRC_ID': 'r1', 'RSRC_TYP_ID': '1', 'RSRC_NAME': 'DR 1', 'RSRC_TYP_NAME': 'Discussion Room', 'CAPACITY': 6},
                {'RSRC_ID': 'r2', 'RSRC_TYP_ID': '2', 'RSRC_NAME': 'LT 1', 'RSRC_TYP_NAME': 'Lecture Theatre', 'CAPACITY': 90},
              ]),
              200,
              request: request);
        case '/MRB002/ResourceReload':
          final list = (jsonDecode(request.bodyFields['parameter']!) as List).first['ResourceList'] as List;
          return http.Response(_freeDay(list.single['RSRC_ID'] as String), 200, request: request);
        case '/DHB001/GetDashBoardDataByStatus':
          return http.Response(jsonEncode({'data': []}), 200, request: request);
        case '/SRB001/NormalBookingConfirmation':
          return http.Response('{}', 200, request: request);
        case '/SRB001/BookingSaving':
          return http.Response(jsonEncode({'result': 'success'}), 200, request: request);
      }
      return http.Response('nf', 404, request: request);
    });
    final client = SessionClient(mock);
    auth = AuthService(client, SecureStorage());
    service = BookingService(client, auth);
  });

  tearDown(() => auth.dispose());

  testWidgets('finds free rooms of the picked types and books one', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => true),
        bookingServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await _settle(tester);

    // Discussion rooms are picked by default; lecture theatres aren't.
    expect(find.text('Discussion Room'), findsOneWidget);

    await tester.tap(find.text('Find free rooms'));
    await _settle(tester);
    expect(find.text('1 room free'), findsOneWidget);
    expect(find.text('DR 1'), findsOneWidget);
    expect(find.text('LT 1'), findsNothing);
    expect(posts.where((p) => p == '/MRB002/ResourceReload'), hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, 'Book'));
    await _settle(tester);
    expect(find.text('Confirm booking'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm booking'));
    await _settle(tester);

    expect(posts, containsAllInOrder(['/SRB001/NormalBookingConfirmation', '/SRB001/BookingSaving']));
    expect(find.textContaining('Booked DR 1 for'), findsOneWidget);
    expect(find.text('No rooms free for this slot'), findsOneWidget, reason: 'the booked room leaves the list');
  });
}
