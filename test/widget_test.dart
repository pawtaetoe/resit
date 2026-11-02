import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/room_booking/presentation/dashboard_screen.dart';
import 'package:resit/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

RoomSlot _slot(String label, {bool available = true}) =>
    RoomSlot(sltId: label, time: label, label: label, status: available ? '1' : '3', available: available);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home shows sign-in status and the tasks', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Book a room'), findsOneWidget);
    expect(find.text('My bookings'), findsOneWidget);
    expect(find.text('Timetable'), findsOneWidget);
  });

  testWidgets('Sign in on Home opens Account and empty fields are flagged', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Student ID'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your student ID'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('Booking screen asks to sign in, with a way there', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Book a room'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to continue'), findsOneWidget);

    await tester.tap(find.text('Go to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsWidgets);
    expect(find.text('Student ID'), findsOneWidget);
  });

  testWidgets('Back sits in the bottom bar and returns Home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My bookings'));
    await tester.pumpAndSettle();
    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    // In the lower part of the screen, not the top corner.
    expect(tester.getCenter(back).dy, greaterThan(tester.view.physicalSize.height / tester.view.devicePixelRatio / 2));

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
  });

  group('slotsInRange', () {
    final slots = [_slot('13:00-13:30'), _slot('13:30-14:00'), _slot('14:00-14:30', available: false)];

    test('returns every slot when the whole range is free', () {
      expect(slotsInRange(slots, 13 * 60, 14 * 60).map((s) => s.label), ['13:00-13:30', '13:30-14:00']);
    });

    test('is empty when part of the range is taken', () {
      expect(slotsInRange(slots, 13 * 60, 14 * 60 + 30), isEmpty);
    });

    test('is empty when the range has a gap', () {
      expect(slotsInRange([_slot('13:00-13:30'), _slot('14:00-14:30')], 13 * 60, 14 * 60 + 30), isEmpty);
    });
  });
}
