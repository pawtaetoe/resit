import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';

void main() {
  final today = DateTime(2026, 11, 16);

  test('today starts at the next half hour; other days at opening', () {
    expect(earliestStart(today, DateTime(2026, 11, 16, 13, 1)), 13 * 60 + 30);
    expect(earliestStart(today, DateTime(2026, 11, 16, 13, 30)), 13 * 60 + 30);
    expect(earliestStart(today, DateTime(2026, 11, 16, 5)), bookingOpenMin);
    expect(earliestStart(DateTime(2026, 11, 17), DateTime(2026, 11, 16, 13)), bookingOpenMin);
  });

  test('nothing is left today after the last half hour', () {
    expect(earliestStart(today, DateTime(2026, 11, 16, 21, 31)), isNull);
    expect(startOptions(today, DateTime(2026, 11, 16, 21, 31)), isEmpty);
    expect(startOptions(today, DateTime(2026, 11, 16, 20, 45)), [21 * 60, 21 * 60 + 30]);
  });

  test('lengths end by closing time', () {
    expect(validDurations(20 * 60), [30, 60, 90, 120]);
    expect(validDurations(bookingOpenMin), bookingLengths);
  });

  test('labels', () {
    expect(hhmm(9 * 60 + 5), '09:05');
    expect(durationLabel(30), '30 min');
    expect(durationLabel(60), '1 h');
    expect(durationLabel(90), '1.5 h');
  });
}
