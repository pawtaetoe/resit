import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';
import 'package:resit/features/timetable/data/upcoming_classes.dart';

ClassSession _s(DateTime day, int start, int end, [String code = 'CSC 2101']) => ClassSession(
      date: day,
      courseCode: code,
      section: 'L1',
      component: 'Lecture',
      startMin: start,
      endMin: end,
      location: 'E2-03-01',
      coinciding: false,
    );

void main() {
  final mon = DateTime(2026, 11, 2);
  final tue = DateTime(2026, 11, 3);
  final classes = [
    _s(tue, 14 * 60, 16 * 60, 'B'),
    _s(mon, 9 * 60, 11 * 60, 'A'),
    _s(tue, 9 * 60, 11 * 60, 'C'),
  ];

  test('during a class: that class, and the next one to start', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 2, 10));
    expect(r.current?.courseCode, 'A');
    expect(r.next?.courseCode, 'C');
  });

  test('between classes: no current, the next one whatever the list order', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 2, 11));
    expect(r.current, isNull);
    expect(r.next?.courseCode, 'C');
    expect(currentAndNextClass(classes, DateTime(2026, 11, 3, 12)).next?.courseCode, 'B');
  });

  test('in the last class: no next one', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 3, 15));
    expect(r.current?.courseCode, 'B');
    expect(r.next, isNull);
  });

  test('nothing once every class has ended', () {
    final r = currentAndNextClass(classes, DateTime(2026, 11, 3, 16));
    expect(r.current, isNull);
    expect(r.next, isNull);
    expect(currentAndNextClass(const [], mon).next, isNull);
  });

  test('saved copies round-trip', () {
    final back = classSessionFromJson(classes.first.toJson());
    expect(back.start, DateTime(2026, 11, 3, 14));
    expect(back.end, DateTime(2026, 11, 3, 16));
    expect(back.courseCode, 'B');
    expect(back.location, 'E2-03-01');
  });
}
