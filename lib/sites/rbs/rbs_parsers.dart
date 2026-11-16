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
