import 'dart:convert';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/sites/rbs/rbs_parsers.dart';
import 'package:resit/sites/rbs/rbs_requests.dart';

/// The student's bookings on RBS, kept briefly so screens opened together
/// share one request.
class BookingsList {
  final RbsRequests _rbs;

  /// Bookings by status are reused this long, so screens opened together
  /// (My bookings, the quota card, Home's next booking) share one request.
  static const ttl = Duration(seconds: 30);

  final DateTime Function() _now;
  final Map<String, ({DateTime at, Future<List<Booking>> bookings})> _bookings = {};

  BookingsList(this._rbs, {required DateTime Function() now}) : _now = now;

  /// Forgets the bookings kept by [get], so the next call asks RBS.
  void invalidate() => _bookings.clear();

  /// The student's bookings with [bookingStatus] ("current" or "history").
  /// Reused for [ttl], and calls made while one is under way share it;
  /// [force] asks RBS again.
  Future<List<Booking>> get({String bookingStatus = 'current', bool force = false}) {
    final kept = _bookings[bookingStatus];
    if (!force && kept != null && _now().difference(kept.at) < ttl) return kept.bookings.then(List.of);
    final future = _fetch(bookingStatus);
    final entry = (at: _now(), bookings: future);
    _bookings[bookingStatus] = entry;
    // A failed request isn't kept.
    future.then((_) {}, onError: (_) {
      if (identical(_bookings[bookingStatus], entry)) _bookings.remove(bookingStatus);
    });
    return future.then(List.of);
  }

  Future<List<Booking>> _fetch(String bookingStatus) async {
    final csrfToken = await _rbs.requireCsrfToken();

    final data = {
      "__RequestVerificationToken": csrfToken,
      "bookingStatus": bookingStatus,
      "resourceCategoryID": "1",
      "resourceName": "",
    };

    final response = await _rbs.post("/DHB001/GetDashBoardDataByStatus", data, referer: RbsRequests.dashboardPage);

    if (response.statusCode != 200) {
      throw Exception("Failed to get bookings: ${response.statusCode}");
    }

    final jsonMap = jsonDecode(response.body);
    final List<dynamic> rawList = jsonMap['data'] ?? [];
    return [for (final e in rawList) if (e is List) bookingFromRow(e.cast<Object?>())];
  }

  /// Every booking that might count toward the weekly quota: current ones
  /// plus history (past bookings earlier in the same week still count).
  Future<List<Booking>> forQuota() async {
    final current = await get(bookingStatus: 'current');
    List<Booking> history = const [];
    try {
      history = await get(bookingStatus: 'history');
    } catch (_) {
      // History is optional; current bookings are the bulk of it.
    }
    final byRef = <String, Booking>{};
    for (final b in [...history, ...current]) {
      byRef[b.bookingRef.isEmpty ? '${b.roomName}|${b.date}|${b.timeRange}' : b.bookingRef] = b;
    }
    return byRef.values.toList();
  }
}
