import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/room_booking/domain/my_bookings.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';

Booking _b(String ref, String date, String time, {String status = 'Confirmed'}) => Booking(
    roomName: 'DR 1',
    date: date,
    timeRange: time,
    academicText: '',
    purpose: '',
    status: status,
    bookingRef: ref,
    cancelId: '');

void main() {
  test('bookings are ordered by date and start time; unreadable ones count as 1970', () {
    expect(bookingSortTime(_b('B1', '9 Nov 2026', '13:30-15:00')), DateTime(2026, 11, 9, 13, 30));
    expect(bookingSortTime(_b('B1', '9 Nov 2026', 'all day')), DateTime(2026, 11, 9));
    expect(bookingSortTime(_b('B1', 'soon', '13:30-15:00')), DateTime(1970));
  });

  test('upcoming: confirmed only, soonest first', () {
    final list = upcomingBookings([
      _b('B1', '10 Nov 2026', '09:00-10:00'),
      _b('B2', '9 Nov 2026', '15:00-16:00'),
      _b('B3', '9 Nov 2026', '08:00-09:00', status: 'Cancelled'),
      _b('B4', '9 Nov 2026', '11:00-12:00'),
    ]);
    expect(list.map((b) => b.bookingRef), ['B4', 'B2', 'B1']);
  });

  test('past: history plus current ones no longer confirmed, newest first', () {
    final list = pastBookings(
      [_b('B1', '1 Nov 2026', '09:00-10:00', status: 'Completed'), _b('B2', '3 Nov 2026', '09:00-10:00')],
      [_b('B3', '9 Nov 2026', '09:00-10:00'), _b('B2', '3 Nov 2026', '09:00-10:00', status: 'Cancelled')],
    );
    expect(list.map((b) => '${b.bookingRef} ${b.status}'), ['B2 Cancelled', 'B1 Completed']);
  });
}
