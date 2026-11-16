import 'dart:async';
import 'dart:convert';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/sites/rbs/rbs_parsers.dart';
import 'package:resit/sites/rbs/rbs_requests.dart';

/// Finding rooms on RBS: the room list and which of their slots are free.
class RoomSearch {
  final RbsRequests _rbs;

  List<Room>? _cachedRooms;

  RoomSearch(this._rbs);

  Future<List<Room>> getRooms({String search = ""}) async {
    if (search.isEmpty && _cachedRooms != null) {
      return _cachedRooms!;
    }

    final csrfToken = await _rbs.requireCsrfToken();

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

    final response = await _rbs.post("/SRB001/SearchSRB001List", data);

    if (response.statusCode != 200) {
      throw Exception("Failed to get rooms: ${response.statusCode}");
    }

    final List<dynamic> jsonList = jsonDecode(response.body);
    final allRooms = [for (final e in jsonList) if (e is Map) roomFromJson(e.cast<String, Object?>())];

    // Every type of room is returned; the search screen filters by type,
    // with discussion and meeting rooms selected by default.
    final typeCounts = <String, int>{};
    for (final r in allRooms) {
      typeCounts[r.rsrcTypName] = (typeCounts[r.rsrcTypName] ?? 0) + 1;
    }
    _rbs.auth.note('Room list: ${allRooms.length} rooms. Types: '
        '${typeCounts.entries.map((e) => '"${e.key}" ×${e.value}').join(', ')}');
    if (search.isEmpty) {
      _cachedRooms = allRooms;
    }
    return allRooms;
  }

  Future<List<RoomWithSlots>> checkAvailability(List<Room> rooms, String date, String startTime, String endTime) async {
    final csrfToken = await _rbs.requireCsrfToken();

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

    final response = await _rbs.post("/MRB002/ResourceReload", data);

    if (response.statusCode != 200) {
      throw Exception("Failed to check availability: ${response.statusCode}");
    }

    return roomsWithSlotsFromReload(response.body, rooms);
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
        await _rbs.requireCsrfToken();
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
}
