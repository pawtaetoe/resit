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

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      rsrcId: json['RSRC_ID'] ?? '',
      rsrcTypId: json['RSRC_TYP_ID'] ?? '',
      rsrcName: json['RSRC_NAME'] ?? '',
      rsrcTypName: json['RSRC_TYP_NAME'] ?? '',
      capacity: json['CAPACITY'] is int 
          ? json['CAPACITY'] 
          : int.tryParse(json['CAPACITY']?.toString() ?? '0') ?? 0,
      isSld: json['IS_SLD'] ?? false,
      eventType: json['Event_Type'] is int 
          ? json['Event_Type'] 
          : int.tryParse(json['Event_Type']?.toString() ?? '0') ?? 0,
      disclaimer: json['DISCLAIMER'] ?? json['Disclaimer'] ?? 'N.A',
    );
  }
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

  factory Booking.fromList(List<dynamic> list) {
    return Booking(
      roomName: list.isNotEmpty && list[0] != null ? list[0].toString() : '',
      date: list.length > 1 && list[1] != null ? list[1].toString() : '',
      timeRange: list.length > 2 && list[2] != null ? list[2].toString() : '',
      academicText: list.length > 3 && list[3] != null ? list[3].toString() : '',
      purpose: list.length > 4 && list[4] != null ? list[4].toString() : '',
      status: list.length > 5 && list[5] != null ? list[5].toString() : '',
      bookingRef: list.length > 6 && list[6] != null ? list[6].toString() : '',
      cancelId: list.length > 7 && list[7] != null ? list[7].toString() : '',
    );
  }
}
