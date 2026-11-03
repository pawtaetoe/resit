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

  test('the class on now comes first', () {
    expect(nextClass(classes, DateTime(2026, 11, 2, 10))?.courseCode, 'A');
  });

  test('otherwise the next one to start, whatever the list order', () {
    expect(nextClass(classes, DateTime(2026, 11, 2, 11))?.courseCode, 'C');
    expect(nextClass(classes, DateTime(2026, 11, 3, 12))?.courseCode, 'B');
  });

  test('none once every class has ended', () {
    expect(nextClass(classes, DateTime(2026, 11, 3, 16)), isNull);
    expect(nextClass(const [], mon), isNull);
  });

  test('saved copies round-trip', () {
    final back = classSessionFromJson(classes.first.toJson());
    expect(back.start, DateTime(2026, 11, 3, 14));
    expect(back.end, DateTime(2026, 11, 3, 16));
    expect(back.courseCode, 'B');
    expect(back.location, 'E2-03-01');
  });
}
