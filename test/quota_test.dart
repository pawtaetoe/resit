import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:resit/features/room_booking/data/quota.dart';

Booking _b(String room, String date, String time, {String status = 'Confirmed', String ref = ''}) => Booking(
    roomName: room,
    date: date,
    timeRange: time,
    academicText: '',
    purpose: '',
    status: status,
    bookingRef: ref.isEmpty ? '$room$date$time' : ref,
    cancelId: '');

void main() {
  final types = {'e2-03-12': discussionRoom, 'boardroom 1': meetingRoom};
  // Wed 4 Nov 2026 -> week of Mon 2 Nov to Sun 8 Nov.
  final day = DateTime(2026, 11, 4);

  test('weeks start on Monday', () {
    expect(weekStart(DateTime(2026, 11, 8)), DateTime(2026, 11, 2));
    expect(weekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
  });

  test('adds up hours per room type within the week only', () {
    final q = WeeklyQuota.from([
      _b('E2-03-12', '2 Nov 2026', '13:00-15:00'),
      _b('E2-03-12', '8 Nov 2026', '09:00-10:30'),
      _b('E2-03-12', '9 Nov 2026', '09:00-11:00'), // next week
      _b('Boardroom 1', '3 Nov 2026', '10:00 - 11:00'),
    ], day, types);
    expect(q.used(discussionRoom), 210);
    expect(q.remaining(discussionRoom), 30);
    expect(q.remaining(meetingRoom), 180);
    expect(q.fits(discussionRoom, 30), isTrue);
    expect(q.fits(discussionRoom, 60), isFalse);
  });

  test('cancelled bookings and duplicates do not count', () {
    final q = WeeklyQuota.from([
      _b('E2-03-12', '2 Nov 2026', '13:00-15:00', ref: 'A'),
      _b('E2-03-12', '2 Nov 2026', '13:00-15:00', ref: 'A'),
      _b('E2-03-12', '3 Nov 2026', '13:00-15:00', status: 'Cancelled'),
    ], day, types);
    expect(q.used(discussionRoom), 120);
  });

  test('guesses the type from the name and reports unknown rooms', () {
    final q = WeeklyQuota.from([
      _b('Meeting Room 5', '2 Nov 2026', '13:00-14:00'),
      _b('Lab 7', '2 Nov 2026', '13:00-14:00'),
    ], day, types);
    expect(q.used(meetingRoom), 60);
    expect(q.unknownBookings, 1);
  });

  test('never goes below zero left', () {
    final q = WeeklyQuota.from([_b('E2-03-12', '2 Nov 2026', '08:00-13:00')], day, types);
    expect(q.remaining(discussionRoom), 0);
  });

  test('room type names are matched by their words, not exact text', () {
    expect(canonicalRoomType('Discussion Room'), discussionRoom);
    expect(canonicalRoomType('Meeting Room'), meetingRoom);
    expect(canonicalRoomType('Meeting Rooms'), meetingRoom);
    expect(canonicalRoomType('MEETING ROOM (Hybrid)'), meetingRoom);
    expect(canonicalRoomType('Lecture Theatre'), isNull);

    final rooms = [
      Room(rsrcId: '1', rsrcTypId: '2', rsrcName: 'MR E2-05-01', rsrcTypName: 'Meeting Rooms', capacity: 12),
    ];
    final q = WeeklyQuota.from([_b('MR E2-05-01', '2 Nov 2026', '10:00-12:00')], day, typeByRoomName(rooms));
    expect(q.used(meetingRoom), 120);
    expect(rooms.single.quotaType, meetingRoom);
  });
}
