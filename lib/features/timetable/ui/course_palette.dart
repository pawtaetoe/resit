import 'package:flutter/painting.dart';
import 'package:resit/features/timetable/data/module_colours.dart';

/// The colour each course is drawn in on the timetable.
class CoursePalette {
  /// Course colours: eight hues that sit with the logo's navy and teal, all
  /// dark enough for white text (at least 5.9:1), none violet. A course
  /// keeps its colour.
  static const colours = [
    Color(0xFF2B5DA8), // blue
    Color(0xFF0B6E78), // teal
    Color(0xFF2E7048), // green
    Color(0xFFA8323E), // crimson
    Color(0xFF963A6A), // plum
    Color(0xFF9A4A0C), // amber
    Color(0xFF45607A), // slate
    Color(0xFF5B6A1E), // olive
  ];

  /// Module → colour (an index into [colours]), from [assignModuleColours].
  final Map<String, int> assignments;

  const CoursePalette(this.assignments);

  /// The colour of course [code]: the one it was given, or one picked from
  /// its code until it has one.
  Color colourOf(String code) => colours[(assignments[moduleKey(code)] ?? code.hashCode.abs()) % colours.length];
}
