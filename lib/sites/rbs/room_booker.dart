import 'dart:convert';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/sites/rbs/rbs_requests.dart';

/// Booking a room on RBS: its two steps, initiate then confirm.
class RoomBooker {
  final RbsRequests _rbs;

  RoomBooker(this._rbs);

  Future<void> book(Room room, List<RoomSlot> slots, String date) async {
    final csrfToken = await _rbs.requireCsrfToken();

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

    final initResp = await _rbs.post("/SRB001/NormalBookingConfirmation", initData);

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

    final confirmResp = await _rbs.post("/SRB001/BookingSaving", confirmData);

    if (confirmResp.statusCode != 200) {
      throw Exception("Confirm failed: ${confirmResp.statusCode}");
    }

    final payload = jsonDecode(confirmResp.body);
    if (payload['result'] != 'success') {
      throw Exception("Booking failed: $payload");
    }
  }
}
