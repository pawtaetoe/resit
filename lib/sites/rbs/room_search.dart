import 'dart:async';
import 'dart:convert';
import 'dart:math';
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

  /// Checks every room, [batchSize] rooms per request and [parallel]
  /// requests at a time, reporting rooms as their answers arrive. RBS
  /// silently drops rooms past about 10 in one request, so batches stay well
  /// under that; batching cuts the number of requests (and rounds) several
  /// times over compared with one room per request.
  ///
  /// Nothing is lost to the cap or to a bad batch: a room missing from its
  /// batch's answer (dropped, or simply without slots) and every room of a
  /// batch that fails twice is checked again on its own, retried once, and
  /// reported with its error if that fails too.
  Stream<RoomCheck> checkEachRoom(
    List<Room> rooms,
    String date,
    String startTime,
    String endTime, {
    int parallel = 6,
    int batchSize = 5,
    Duration timeout = const Duration(seconds: 20),
  }) {
    late final StreamController<RoomCheck> controller;
    var cancelled = false;
    final batches = [
      for (var i = 0; i < rooms.length; i += batchSize) rooms.sublist(i, min(i + batchSize, rooms.length)),
    ];
    var next = 0;
    var requests = 0;
    var singles = 0;

    void report(RoomCheck check) {
      if (!cancelled) controller.add(check);
    }

    Future<List<RoomWithSlots>> ask(List<Room> group) async {
      for (var attempt = 1;; attempt++) {
        try {
          requests++;
          return await checkAvailability(group, date, startTime, endTime).timeout(timeout);
        } catch (e) {
          if (attempt >= 2 || cancelled) rethrow;
        }
      }
    }

    Future<void> checkAlone(Room room) async {
      singles++;
      try {
        final found = await ask([room]);
        report(RoomCheck(room, result: found.isEmpty ? null : found.first));
      } catch (e) {
        report(RoomCheck(room, error: e));
      }
    }

    Future<void> worker() async {
      while (!cancelled && next < batches.length) {
        final group = batches[next++];
        if (group.length == 1) {
          await checkAlone(group.single);
          continue;
        }
        Map<String, RoomWithSlots> found;
        try {
          found = {for (final r in await ask(group)) r.room.rsrcId: r};
        } catch (_) {
          found = const {};
        }
        final missing = <Room>[];
        for (final room in group) {
          final hit = found[room.rsrcId];
          hit == null ? missing.add(room) : report(RoomCheck(room, result: hit));
        }
        for (final room in missing) {
          if (cancelled) return;
          await checkAlone(room);
        }
      }
    }

    Future<void> run() async {
      try {
        // Validate the session once up front, so the parallel requests don't
        // each re-check it at the same moment.
        await _rbs.requireCsrfToken();
        await Future.wait([for (var i = 0; i < parallel && i < batches.length; i++) worker()]);
        _rbs.auth.note('Room search: ${rooms.length} rooms in $requests requests '
            '(${batches.length} batches of up to $batchSize, $singles rooms checked alone)');
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
