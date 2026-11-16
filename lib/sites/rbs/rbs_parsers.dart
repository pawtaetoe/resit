import 'dart:convert';
import 'package:resit/features/room_booking/domain/rooms.dart';

// Reading RBS's replies into the app's models. RBS sends loosely typed JSON
// (numbers sometimes as text, missing fields), so every value is checked
// for its type instead of being cast.

String _str(Object? v, [String fallback = '']) => v == null ? fallback : (v is String ? v : '$v');
int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()) ?? 0);
bool _bool(Object? v) => v is bool ? v : (v is String ? v.toLowerCase() == 'true' : false);

/// A room from RBS's room search.
Room roomFromJson(Map<String, Object?> json) => Room(
      rsrcId: _str(json['RSRC_ID']),
      rsrcTypId: _str(json['RSRC_TYP_ID']),
      rsrcName: _str(json['RSRC_NAME']),
      rsrcTypName: _str(json['RSRC_TYP_NAME']),
      capacity: _int(json['CAPACITY']),
      isSld: _bool(json['IS_SLD']),
      eventType: _int(json['Event_Type']),
      disclaimer: _str(json['DISCLAIMER'] ?? json['Disclaimer'], 'N.A'),
    );

/// A booking from one row of RBS's bookings table (a list of cells).
Booking bookingFromRow(List<Object?> row) {
  String cell(int i) => i < row.length ? _str(row[i]) : '';
  return Booking(
    roomName: cell(0),
    date: cell(1),
    timeRange: cell(2),
    academicText: cell(3),
    purpose: cell(4),
    status: cell(5),
    bookingRef: cell(6),
    cancelId: cell(7),
  );
}

/// The slots of [originalRooms] in a ResourceReload answer (HTML with one
/// div per slot). Rooms the answer doesn't mention are left out.
List<RoomWithSlots> roomsWithSlotsFromReload(String htmlText, List<Room> originalRooms) {
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

/// The encrypted ID in an EncryptDecryptFunc answer (base64 text, maybe
/// with a trailing newline), or null if the answer is something else, such
/// as an error page.
String? encryptedIdFrom(String body) {
  final text = body.trim();
  if (text.isEmpty || !RegExp(r'^[A-Za-z0-9+/=_\-]+$').hasMatch(text)) return null;
  return text;
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
