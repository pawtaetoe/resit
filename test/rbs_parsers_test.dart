import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/sites/rbs/rbs_parsers.dart';

Room _room(String id) =>
    Room(rsrcId: id, rsrcTypId: '1', rsrcName: 'DR $id', rsrcTypName: 'Discussion Room', capacity: 6);

void main() {
  group('roomsWithSlotsFromReload', () {
    test('reads each slot div, whatever the attribute quoting', () {
      const html = '<div data-rsrcid="r1" data-sltid="s1" data-slot=\'13:00\' data-slotstatus=1 data-srno="4">'
          ' 13:00-13:30 </div>'
          '<div data-rsrcid=&quot;r1&quot; data-sltid="s2" data-slotstatus="3">13:30-14:00</div>';
      final result = roomsWithSlotsFromReload(html, [_room('r1')]);
      expect(result, hasLength(1));
      final slots = result.single.slots;
      expect(slots.map((s) => s.label), ['13:00-13:30', '13:30-14:00']);
      expect(slots.map((s) => s.available), [true, false]);
      expect(slots.first.time, '13:00');
      expect(slots.first.srno, 4);
      expect(slots.last.status, '3');
    });

    test('leaves out rooms that were not asked about', () {
      const html = '<div data-rsrcid="r9" data-slotstatus="1">13:00-13:30</div>';
      expect(roomsWithSlotsFromReload(html, [_room('r1')]), isEmpty);
    });
  });
}
