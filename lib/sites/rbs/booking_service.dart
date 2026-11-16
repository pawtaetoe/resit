import 'package:resit/core/network/session_client.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/sites/rbs/booking_canceller.dart';
import 'package:resit/sites/rbs/bookings_list.dart';
import 'package:resit/sites/rbs/rbs_requests.dart';
import 'package:resit/sites/rbs/room_booker.dart';
import 'package:resit/sites/rbs/room_search.dart';

/// Room booking on RBS, as the app's screens use it. Each job lives in its
/// own class next to this file (room search, booking, the bookings list,
/// cancelling); they share one form token look-up, and booking or
/// cancelling forgets the kept bookings.
class BookingService {
  final RoomSearch _search;
  final RoomBooker _booker;
  final BookingsList _bookings;
  final BookingCanceller _canceller;

  BookingService(SessionClient client, AuthService auth, {DateTime Function()? now})
      : this._(RbsRequests(client, auth), now ?? DateTime.now);

  BookingService._(RbsRequests rbs, DateTime Function() now)
      : _search = RoomSearch(rbs),
        _booker = RoomBooker(rbs),
        _bookings = BookingsList(rbs, now: now),
        _canceller = BookingCanceller(rbs);

  /// Forgets the bookings kept by [getBookings], so the next call asks RBS.
  /// Booking and cancelling here do this themselves.
  void invalidateBookings() => _bookings.invalidate();

  Future<List<Room>> getRooms({String search = ""}) => _search.getRooms(search: search);

  Future<List<RoomWithSlots>> checkAvailability(List<Room> rooms, String date, String startTime, String endTime) =>
      _search.checkAvailability(rooms, date, startTime, endTime);

  /// Checks every room, a few rooms per request and a few requests at once,
  /// reporting rooms as their answers arrive (see [RoomSearch.checkEachRoom]).
  Stream<RoomCheck> checkEachRoom(
    List<Room> rooms,
    String date,
    String startTime,
    String endTime, {
    int parallel = 6,
    int batchSize = 5,
    Duration timeout = const Duration(seconds: 20),
  }) =>
      _search.checkEachRoom(rooms, date, startTime, endTime,
          parallel: parallel, batchSize: batchSize, timeout: timeout);

  Future<void> initiateAndConfirmBooking(Room room, List<RoomSlot> slots, String date) async {
    try {
      await _booker.book(room, slots, date);
    } finally {
      // Booked, or maybe partly: either way the kept list is out of date.
      invalidateBookings();
    }
  }

  /// The student's bookings with [bookingStatus] ("current" or "history").
  /// Reused for [BookingsList.ttl], and calls made while one is under way
  /// share it; [force] asks RBS again.
  Future<List<Booking>> getBookings({String bookingStatus = 'current', bool force = false}) =>
      _bookings.get(bookingStatus: bookingStatus, force: force);

  /// Every booking that might count toward the weekly quota: current ones
  /// plus history (past bookings earlier in the same week still count).
  Future<List<Booking>> getQuotaBookings() => _bookings.forQuota();

  /// The reason sent with a cancellation (RBS asks for one).
  static const cancelReason = 'No longer needed';

  /// Cancels the booking with reference [bookingRef] (e.g.
  /// "20261117BKG000020").
  Future<void> cancelBooking(String bookingRef, {String reason = cancelReason}) async {
    try {
      await _canceller.cancel(bookingRef, reason);
    } finally {
      invalidateBookings();
    }
  }
}
