import 'dart:convert';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/features/room_booking/data/models.dart';

class BookingService {
  final SessionClient client;
  final AuthService auth;

  static const String base = "https://rbs.singaporetech.edu.sg";
  static const Set<String> roomTypes = {"Discussion Room", "Meeting Room"};
  
  List<Room>? _cachedRooms;

  BookingService(this.client, this.auth);

  Future<List<Room>> getRooms({String search = ""}) async {
    if (search.isEmpty && _cachedRooms != null) {
      return _cachedRooms!;
    }

    final csrfToken = await auth.getCsrfToken();
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
    
    final filtered = allRooms.where((r) => roomTypes.contains(r.rsrcTypName)).toList();
    if (search.isEmpty) {
      _cachedRooms = filtered;
    }
    return filtered;
  }

  Future<List<RoomWithSlots>> checkAvailability(
      List<Room> rooms, String date, String startTime, String endTime) async {
    final csrfToken = await auth.getCsrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");

    final resourceList = rooms.map((r) => {
      "RSRC_ID": r.rsrcId,
      "IS_SLD": r.isSld,
      "Event_Type": r.eventType,
      "Disclaimer": r.disclaimer,
    }).toList();

    final parameter = [{
      "MRB002Date": date, // e.g. "18 May 2026"
      "MRB002StartTime": startTime, // e.g. "00:00"
      "MRB002EndTime": endTime, // e.g. "23:59"
      "ResourceList": resourceList,
    }];

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

  List<RoomWithSlots> _parseReloadHtml(String htmlText, List<Room> originalRooms) {
    final slotDivRe = RegExp(r'<div\s+([^>]*?data-rsrcid=[^>]*?)>\s*([^<]*?)\s*<', caseSensitive: false);
    final dataAttrRe = RegExp(r"data-([a-z]+)=(?:'([^']*)'|&quot;([^&]*)&quot;|\x22([^\x22]*)\x22|([^\s>]+))", caseSensitive: false);

    Map<String, Room> roomMap = { for (var r in originalRooms) r.rsrcId : r };
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
    final csrfToken = await auth.getCsrfToken();
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
}
