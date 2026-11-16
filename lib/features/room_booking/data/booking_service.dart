import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as parser;
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/features/room_booking/data/models.dart';

class BookingService {
  final SessionClient client;
  final AuthService auth;

  static const String base = "https://rbs.singaporetech.edu.sg";

  List<Room>? _cachedRooms;

  /// Bookings by status are reused this long, so screens opened together
  /// (My bookings, the quota card, Home's next booking) share one request.
  static const bookingsTtl = Duration(seconds: 30);

  final DateTime Function() _now;
  final Map<String, ({DateTime at, Future<List<Booking>> bookings})> _bookings = {};
  Future<String?>? _csrfInFlight;

  BookingService(this.client, this.auth, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The RBS form token. Requests that start together share one look-up
  /// (the auth service keeps the token itself between look-ups).
  Future<String?> _csrfToken() {
    return _csrfInFlight ??= auth.getCsrfToken().whenComplete(() => _csrfInFlight = null);
  }

  /// Forgets the bookings kept by [getBookings], so the next call asks RBS.
  /// Booking and cancelling here do this themselves.
  void invalidateBookings() => _bookings.clear();

  Future<List<Room>> getRooms({String search = ""}) async {
    if (search.isEmpty && _cachedRooms != null) {
      return _cachedRooms!;
    }

    final csrfToken = await _csrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");

    final data = {
      "__RequestVerificationToken": csrfToken,
      "CapacityOperator": "<",
      "SingleCapacity": "",
      "MinCapacity": "",
      "MaxCapacity": "",
      "campusID": "",
      "buildingID": "",
      "bookingstatus": "All",
      "faciequip": "facilities",
      "BookingStatus": "All",
      "Search": search,
      "ResourceType": "",
      "LocationID": "",
    };

    final response = await client.post(
      Uri.parse("$base/SRB001/SearchSRB001List"),
      headers: {
        "accept": "application/json, text/javascript, */*; q=0.01",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": "$base/SRB001/SRB001Page",
        "origin": base,
      },
      body: data,
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to get rooms: ${response.statusCode}");
    }

    final List<dynamic> jsonList = jsonDecode(response.body);
    final allRooms = jsonList.map((e) => Room.fromJson(e)).toList();

    // Every type of room is returned; the search screen filters by type,
    // with discussion and meeting rooms selected by default.
    final typeCounts = <String, int>{};
    for (final r in allRooms) {
      typeCounts[r.rsrcTypName] = (typeCounts[r.rsrcTypName] ?? 0) + 1;
    }
    auth.note('Room list: ${allRooms.length} rooms. Types: '
        '${typeCounts.entries.map((e) => '"${e.key}" ×${e.value}').join(', ')}');
    if (search.isEmpty) {
      _cachedRooms = allRooms;
    }
    return allRooms;
  }

  Future<List<RoomWithSlots>> checkAvailability(List<Room> rooms, String date, String startTime, String endTime) async {
    final csrfToken = await _csrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");

    final resourceList = rooms
        .map((r) => {
              "RSRC_ID": r.rsrcId,
              "IS_SLD": r.isSld,
              "Event_Type": r.eventType,
              "Disclaimer": r.disclaimer,
            })
        .toList();

    final parameter = [
      {
        "MRB002Date": date, // e.g. "18 May 2026"
        "MRB002StartTime": startTime, // e.g. "00:00"
        "MRB002EndTime": endTime, // e.g. "23:59"
        "ResourceList": resourceList,
      }
    ];

    final data = {
      "__RequestVerificationToken": csrfToken,
      "parameter": jsonEncode(parameter),
      "bookingstatus": "All",
      "_rsrcCat": "facilities",
    };

    final response = await client.post(
      Uri.parse("$base/MRB002/ResourceReload"),
      headers: {
        "accept": "application/json, text/javascript, */*; q=0.01",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": "$base/SRB001/SRB001Page",
        "origin": base,
      },
      body: data,
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to check availability: ${response.statusCode}");
    }

    return _parseReloadHtml(response.body, rooms);
  }

  /// Checks every room separately, [parallel] at a time, and reports each
  /// room as soon as its answer arrives. One room per request keeps every
  /// request well under the server's cap of 10 rooms (a single request for
  /// all rooms silently drops the rest), and running a few at once makes the
  /// whole search much faster than one big request. A room that fails is
  /// retried once; if it fails again it's reported with its error, so one
  /// slow room doesn't sink the search.
  Stream<RoomCheck> checkEachRoom(
    List<Room> rooms,
    String date,
    String startTime,
    String endTime, {
    int parallel = 6,
    Duration timeout = const Duration(seconds: 20),
  }) {
    late final StreamController<RoomCheck> controller;
    var cancelled = false;
    var next = 0;

    Future<RoomWithSlots?> checkOne(Room room) async {
      for (var attempt = 1;; attempt++) {
        try {
          final result = await checkAvailability([room], date, startTime, endTime).timeout(timeout);
          return result.isEmpty ? null : result.first;
        } catch (e) {
          if (attempt >= 2 || cancelled) rethrow;
        }
      }
    }

    Future<void> worker() async {
      while (!cancelled && next < rooms.length) {
        final room = rooms[next++];
        try {
          final result = await checkOne(room);
          if (!cancelled) controller.add(RoomCheck(room, result: result));
        } catch (e) {
          if (!cancelled) controller.add(RoomCheck(room, error: e));
        }
      }
    }

    Future<void> run() async {
      try {
        // Validate the session once up front, so the parallel requests don't
        // each re-check it at the same moment.
        final token = await _csrfToken();
        if (token == null) throw Exception("Could not get CSRF token.");
        await Future.wait([for (var i = 0; i < parallel && i < rooms.length; i++) worker()]);
      } catch (e, st) {
        if (!cancelled) controller.addError(e, st);
      } finally {
        await controller.close();
      }
    }

    controller = StreamController<RoomCheck>(
      onListen: run,
      onCancel: () => cancelled = true,
    );
    return controller.stream;
  }

  List<RoomWithSlots> _parseReloadHtml(String htmlText, List<Room> originalRooms) {
    final slotDivRe = RegExp(r'<div\s+([^>]*?data-rsrcid=[^>]*?)>\s*([^<]*?)\s*<', caseSensitive: false);
    final dataAttrRe =
        RegExp(r"data-([a-z]+)=(?:'([^']*)'|&quot;([^&]*)&quot;|\x22([^\x22]*)\x22|([^\s>]+))", caseSensitive: false);

    Map<String, Room> roomMap = {for (var r in originalRooms) r.rsrcId: r};
    Map<String, List<RoomSlot>> slotsMap = {};

    for (final match in slotDivRe.allMatches(htmlText)) {
      final attrStr = match.group(1) ?? "";
      final label = match.group(2)?.trim() ?? "";

      Map<String, String> attrs = {};
      for (final attrMatch in dataAttrRe.allMatches(attrStr)) {
        final key = attrMatch.group(1)?.toLowerCase() ?? "";
        final val = attrMatch.group(2) ?? attrMatch.group(3) ?? attrMatch.group(4) ?? attrMatch.group(5) ?? "";
        attrs[key] = val;
      }

      final rsrcId = attrs['rsrcid'];
      if (rsrcId == null) continue;

      final statusCode = attrs['slotstatus'] ?? "";
      final available = statusCode == "1";

      final slot = RoomSlot(
        sltId: attrs['sltid'] ?? "",
        time: attrs['slot'] ?? "",
        label: label,
        status: statusCode,
        available: available,
        eventType: int.tryParse(attrs['eventtype'] ?? ""),
        srno: int.tryParse(attrs['srno'] ?? ""),
      );

      slotsMap.putIfAbsent(rsrcId, () => []).add(slot);
    }

    List<RoomWithSlots> result = [];
    for (final entry in slotsMap.entries) {
      final room = roomMap[entry.key];
      if (room != null) {
        result.add(RoomWithSlots(room, entry.value));
      }
    }
    return result;
  }

  Future<void> initiateAndConfirmBooking(Room room, List<RoomSlot> slots, String date) async {
    try {
      await _book(room, slots, date);
    } finally {
      // Booked, or maybe partly: either way the kept list is out of date.
      invalidateBookings();
    }
  }

  Future<void> _book(Room room, List<RoomSlot> slots, String date) async {
    final csrfToken = await _csrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");

    // Initiate
    List<Map<String, dynamic>> slotList = [];
    for (int i = 0; i < slots.length; i++) {
      final sl = slots[i];
      slotList.add({
        "SRNO": sl.srno ?? (i + 1),
        "SLT_ID": sl.sltId,
        "SLT_Time": sl.time,
        "SLT_Desc": sl.label,
        "encryptedSlotStatus": null,
        "SLT_STATUS": int.tryParse(sl.status) ?? 1,
        "encryptedSLT_Time": null,
      });
    }

    final initData = {
      "__RequestVerificationToken": csrfToken,
      "RSRC_ID": room.rsrcId,
      "RSRC_TYP_ID": room.rsrcTypId,
      "SearchDate": date,
      "SlotList": jsonEncode(slotList),
      "APPRV_EXEMP": "false",
      "SUPPT_EXEMP": "false",
      "checkReorNot": "0",
      "IS_IN4SIT": "false",
      "IS_SUPT": "false",
      "IS_APPRVL": "false",
    };

    final initResp = await client.post(
      Uri.parse("$base/SRB001/NormalBookingConfirmation"),
      headers: {
        "accept": "application/json, text/javascript, */*; q=0.01",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": "$base/SRB001/SRB001Page",
        "origin": base,
      },
      body: initData,
    );

    if (initResp.statusCode != 200) {
      throw Exception("Initiate failed");
    }

    // Confirm
    final confirmData = {
      "__RequestVerificationToken": csrfToken,
      "RSRC_TYP_ID": room.rsrcTypId,
      "NUM_ATTND": "2",
      "Event_TypeText": "",
      "Acad_Text": "",
      "Purpose": "proj",
      "supptList": "[]",
      "OVERWRITE": "0",
      "slcPurpose": "",
    };

    final confirmResp = await client.post(
      Uri.parse("$base/SRB001/BookingSaving"),
      headers: {
        "accept": "application/json, text/javascript, */*; q=0.01",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": "$base/SRB001/SRB001Page",
        "origin": base,
      },
      body: confirmData,
    );

    if (confirmResp.statusCode != 200) {
      throw Exception("Confirm failed: ${confirmResp.statusCode}");
    }

    final payload = jsonDecode(confirmResp.body);
    if (payload['result'] != 'success') {
      throw Exception("Booking failed: $payload");
    }
  }

  /// The student's bookings with [bookingStatus] ("current" or "history").
  /// Reused for [bookingsTtl], and calls made while one is under way share
  /// it; [force] asks RBS again.
  Future<List<Booking>> getBookings({String bookingStatus = 'current', bool force = false}) {
    final kept = _bookings[bookingStatus];
    if (!force && kept != null && _now().difference(kept.at) < bookingsTtl) return kept.bookings.then(List.of);
    final future = _fetchBookings(bookingStatus);
    final entry = (at: _now(), bookings: future);
    _bookings[bookingStatus] = entry;
    // A failed request isn't kept.
    future.then((_) {}, onError: (_) {
      if (identical(_bookings[bookingStatus], entry)) _bookings.remove(bookingStatus);
    });
    return future.then(List.of);
  }

  Future<List<Booking>> _fetchBookings(String bookingStatus) async {
    final csrfToken = await _csrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");

    final data = {
      "__RequestVerificationToken": csrfToken,
      "bookingStatus": bookingStatus,
      "resourceCategoryID": "1",
      "resourceName": "",
    };

    final response = await client.post(
      Uri.parse("$base/DHB001/GetDashBoardDataByStatus"),
      headers: {
        "accept": "application/json, text/javascript, */*; q=0.01",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": "$base/DHB001/DHB001Page",
        "origin": base,
      },
      body: data,
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to get bookings: ${response.statusCode}");
    }

    final jsonMap = jsonDecode(response.body);
    final List<dynamic> rawList = jsonMap['data'] ?? [];
    return rawList.map((e) => Booking.fromList(List<dynamic>.from(e))).toList();
  }

  /// Every booking that might count toward the weekly quota: current ones
  /// plus history (past bookings earlier in the same week still count).
  Future<List<Booking>> getQuotaBookings() async {
    final current = await getBookings(bookingStatus: 'current');
    List<Booking> history = const [];
    try {
      history = await getBookings(bookingStatus: 'history');
    } catch (_) {
      // History is optional; current bookings are the bulk of it.
    }
    final byRef = <String, Booking>{};
    for (final b in [...history, ...current]) {
      byRef[b.bookingRef.isEmpty ? '${b.roomName}|${b.date}|${b.timeRange}' : b.bookingRef] = b;
    }
    return byRef.values.toList();
  }

  /// The reason sent with a cancellation (RBS asks for one).
  static const cancelReason = 'No longer needed';

  Future<void> cancelBooking(String cancelId, {String reason = cancelReason}) async {
    try {
      await _cancel(cancelId, reason);
    } finally {
      invalidateBookings();
    }
  }

  /// Cancels a booking the way RBS's own "Cancel" button does: one POST to
  /// SaveToCancel with the booking's encrypted ID, which answers "1" when
  /// it's done.
  Future<void> _cancel(String cancelId, String reason) async {
    final id = bookingIdFrom(cancelId);
    if (id.isEmpty) throw Exception("This booking can't be cancelled from the app.");
    final csrfToken = await _csrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");

    final response = await client.post(
      Uri.parse("$base/DHB001/SaveToCancel"),
      headers: {
        "accept": "application/json, text/javascript, */*; q=0.01",
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": "$base/DHB001/DHB001Page",
        "origin": base,
      },
      body: {
        "__RequestVerificationToken": csrfToken,
        "bookID[]": id,
        "reason": reason,
      },
    );
    if (response.statusCode != 200) {
      throw Exception("RBS answered ${response.statusCode} to the cancellation.");
    }
    if (!cancelSucceeded(response.body)) {
      throw Exception("RBS didn't confirm the cancellation (${response.body.trim()}). Check My bookings.");
    }
  }
}

/// The encrypted booking ID RBS expects, from the bookings list's ID
/// column: either the ID itself, or the checkbox or button that carries it.
String bookingIdFrom(String raw) {
  final text = raw.trim();
  if (!text.contains('<')) return text;
  final el = parser.parseFragment(text).querySelector('input[value], button[value], [data-id], [data-bookid]');
  if (el == null) return '';
  return (el.attributes['value'] ?? el.attributes['data-id'] ?? el.attributes['data-bookid'] ?? '').trim();
}

/// RBS answers a successful cancellation with "1" (as a JSON string).
bool cancelSucceeded(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded == 1 || decoded == '1' || decoded == true;
  } catch (_) {
    return body.trim() == '1';
  }
}
