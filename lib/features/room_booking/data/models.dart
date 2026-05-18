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
