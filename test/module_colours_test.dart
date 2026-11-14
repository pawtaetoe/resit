import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/timetable/data/module_colours.dart';

void main() {
  test('modules seen together get different colours while there are enough', () {
    final colours = assignModuleColours({}, ['INF 2004', 'CSC 2101', 'CSC 3104', 'INF 2002', 'USI 2001', 'UDE 2222'], 8);
    expect(colours.values.toSet(), hasLength(6));
    expect(colours.keys, contains('CSC2101'), reason: 'spaces dropped: "CSC 2101" and "CSC2101" are one module');
  });

  test('a module keeps its colour when others are added later', () {
    final first = assignModuleColours({}, ['CSC 2101', 'INF 2004'], 8);
    final later = assignModuleColours(first, ['ZZZ 1000', 'AAA 1000', 'CSC 2101'], 8);
    expect(later['CSC2101'], first['CSC2101']);
    expect(later['INF2004'], first['INF2004']);
    expect(later.values.toSet(), hasLength(4));
  });

  test('more modules than colours reuse the least used colour', () {
    final colours = assignModuleColours({}, [for (var i = 0; i < 10; i++) 'MOD $i'], 8);
    final counts = <int, int>{};
    for (final c in colours.values) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    expect(counts.values.reduce((a, b) => a > b ? a : b), 2);
  });
}
