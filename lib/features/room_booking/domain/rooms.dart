class Room {
  final String rsrcId;
  final String rsrcTypId;
  final String rsrcName;
  final String rsrcTypName;
  final int capacity;
  final bool isSld;
  final int eventType;
  final String disclaimer;

  Room({
    required this.rsrcId,
    required this.rsrcTypId,
    required this.rsrcName,
    required this.rsrcTypName,
    required this.capacity,
    this.isSld = false,
    this.eventType = 0,
    this.disclaimer = "N.A",
  });
}

class RoomSlot {
  final String sltId;
  final String time;
  final String label;
  final String status; // '1' available, '3' confirmed
  final bool available;
  final int? eventType;
  final int? srno;

  RoomSlot({
    required this.sltId,
    required this.time,
    required this.label,
    required this.status,
    required this.available,
    this.eventType,
    this.srno,
  });
}

class RoomWithSlots {
  final Room room;
  final List<RoomSlot> slots;

  RoomWithSlots(this.room, this.slots);
}

class Booking {
  final String roomName;
  final String date;
  final String timeRange;
  final String academicText;
  final String purpose;
  final String status;
  final String bookingRef;
  final String cancelId;

  Booking({
    required this.roomName,
    required this.date,
    required this.timeRange,
    required this.academicText,
    required this.purpose,
    required this.status,
    required this.bookingRef,
    required this.cancelId,
  });
}

/// The answer for one room from a per-room availability check: its slots,
/// null if the server returned none, or the error if it couldn't be checked.
class RoomCheck {
  final Room room;
  final RoomWithSlots? result;
  final Object? error;

  RoomCheck(this.room, {this.result, this.error});
}
