import 'dart:convert';

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

  testWidgets('Home shows sign-in status; the tasks are on the Services tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to get started'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    for (final task in ['Book a room', 'My bookings', 'Timetable', 'Exam results', 'Academic calendar']) {
      await tester.scrollUntilVisible(find.text(task), 100);
      expect(find.text(task), findsOneWidget, reason: task);
    }
  });

  testWidgets('Home shows the next class from the saved timetable', (tester) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    SharedPreferences.setMockInitialValues({
      'upcoming_classes': jsonEncode([
        {
          'date': tomorrow.toIso8601String(),
          'course': 'CSC 2101',
          'section': 'L1',
          'component': 'Lecture',
          'start': 9 * 60,
          'end': 11 * 60,
          'location': 'E2-03-01',
        },
      ]),
    });
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    expect(find.text('Next class: CSC 2101 Lecture'), findsOneWidget);
    expect(find.textContaining('Now:'), findsNothing);
    expect(find.text('Tomorrow, 09:00 – 11:00 · E2-03-01'), findsOneWidget);
  });

  testWidgets('During a class, Home shows it and the next one', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minute = now.hour * 60 + now.minute;
    Map<String, Object?> cls(DateTime day, String code, int start, int end) => {
          'date': day.toIso8601String(),
          'course': code,
          'section': 'L1',
          'component': 'Lecture',
          'start': start,
          'end': end,
          'location': 'E2-03-01',
        };
    SharedPreferences.setMockInitialValues({
      'upcoming_classes': jsonEncode([
        cls(today, 'CSC 1001', minute - 30, minute + 60),
        cls(today.add(const Duration(days: 1)), 'CSC 2101', 9 * 60, 11 * 60),
      ]),
    });
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    expect(find.text('Now: CSC 1001 Lecture'), findsOneWidget);
    expect(find.text('Next class: CSC 2101 Lecture'), findsOneWidget);
  });

  testWidgets('GPA is hidden on Home until the eye is tapped', (tester) async {
    SharedPreferences.setMockInitialValues({
      'academic_record': jsonEncode({
        'creditsEarned': 60,
        'cumulativeGpa': '4.12',
        'latestTermGpa': '4.30',
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    });
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    // Credits aren't grades, so they stay visible.
    expect(find.text('60'), findsOneWidget);
    expect(find.text('4.12'), findsNothing);
    expect(find.textContaining('4.30'), findsNothing);
    expect(find.text('•••'), findsOneWidget);

    await tester.tap(find.byTooltip('Show grades'));
    await tester.pumpAndSettle();
    expect(find.text('4.12'), findsOneWidget);
    expect(find.text('cumulative GPA · last term 4.30'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide grades'));
    await tester.pumpAndSettle();
    expect(find.text('4.12'), findsNothing);
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

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book a room'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to continue'), findsOneWidget);

    await tester.tap(find.text('Go to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsWidgets);
    expect(find.text('Student ID'), findsOneWidget);
  });

  testWidgets('Back sits in the bottom bar and returns to Services', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReSitApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My bookings'));
    await tester.pumpAndSettle();
    final back = find.byTooltip('Back');
    expect(back, findsOneWidget);
    // In the lower part of the screen, not the top corner.
    expect(tester.getCenter(back).dy, greaterThan(tester.view.physicalSize.height / tester.view.devicePixelRatio / 2));

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Book a room'), findsOneWidget);
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
