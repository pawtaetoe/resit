import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/features/timetable/ui/week_grid_layout.dart';

ClassSession _class(String code, int start, int end) => ClassSession(
      date: DateTime(2026, 10, 5),
      courseCode: code,
      section: 'L1',
      component: 'Lecture',
      startMin: start,
      endMin: end,
      location: 'E2-03-01',
      coinciding: false,
    );

void main() {
  group('placeDay', () {
    test('classes apart in time each get the whole column', () {
      final placed = WeekGridLayout.placeDay([_class('B', 13 * 60, 15 * 60), _class('A', 9 * 60, 11 * 60)]);
      expect(placed.map((p) => (p.session.courseCode, p.lane, p.laneCount)), [('A', 0, 1), ('B', 0, 1)]);
    });

    test('overlapping classes share the column side by side', () {
      final placed = WeekGridLayout.placeDay([
        _class('A', 9 * 60, 11 * 60),
        _class('B', 10 * 60, 11 * 60),
        // Overlaps both: a third lane.
        _class('C', 10 * 60 + 30, 12 * 60),
      ]);
      expect(placed.map((p) => (p.session.courseCode, p.lane, p.laneCount)), [('A', 0, 3), ('B', 1, 3), ('C', 2, 3)]);
    });

    test('a lane is reused once its class has ended', () {
      final placed = WeekGridLayout.placeDay([
        _class('A', 9 * 60, 10 * 60),
        _class('B', 9 * 60 + 15, 12 * 60),
        _class('C', 10 * 60, 11 * 60),
      ]);
      expect(placed.map((p) => (p.session.courseCode, p.lane, p.laneCount)), [('A', 0, 2), ('B', 1, 2), ('C', 0, 2)]);
    });
  });

  group('WeekGridLayout.fit', () {
    test('spans 08:00 to 18:00 by default', () {
      final layout = WeekGridLayout.fit(const [], hourHeight: 60);
      expect((layout.startHour, layout.endHour), (8, 18));
      expect(layout.height, 600);
    });

    test('stretches to whole hours around early and late classes', () {
      final layout = WeekGridLayout.fit([_class('A', 7 * 60 + 30, 9 * 60), _class('B', 18 * 60, 19 * 60 + 15)],
          hourHeight: 60);
      expect((layout.startHour, layout.endHour), (7, 20));
      expect(layout.minuteTop(7 * 60 + 30), 30);
      expect(layout.hourTop(9), 120);
    });

    test('a short class is still tall enough to tap', () {
      final layout = WeekGridLayout.fit(const [], hourHeight: 60);
      expect(layout.blockHeight(_class('A', 9 * 60, 9 * 60 + 15)), 40);
      expect(layout.blockHeight(_class('A', 9 * 60, 11 * 60)), 118);
    });
  });
}
