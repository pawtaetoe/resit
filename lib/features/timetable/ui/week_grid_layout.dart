import 'package:resit/features/timetable/domain/class_session.dart';

/// A class placed in its day's column: the lane it takes, and how many lanes
/// its group of overlapping classes shares the column with.
class PlacedSession {
  final ClassSession session;
  final int lane;
  final int laneCount;

  PlacedSession(this.session, this.lane, this.laneCount);
}

/// Where things go on the week grid: the hours it spans, and the height and
/// position of each class. Pure layout maths, no widgets.
class WeekGridLayout {
  /// The column of hour labels down the left.
  static const timeColumnWidth = 44.0;

  /// Monday to Friday.
  static const dayCount = 5;

  /// The first hour line shown (08:00, or earlier for an earlier class).
  final int startHour;

  /// The last hour line shown (18:00, or later for a later class).
  final int endHour;

  /// An hour's height in pixels.
  final double hourHeight;

  const WeekGridLayout({required this.startHour, required this.endHour, required this.hourHeight});

  /// Spans 08:00 to 18:00, stretched to whole hours that fit every class in
  /// [sessions].
  factory WeekGridLayout.fit(Iterable<ClassSession> sessions, {required double hourHeight}) {
    final minStart = sessions.map((s) => s.startMin).fold<int>(8 * 60, (a, b) => a < b ? a : b);
    final maxEnd = sessions.map((s) => s.endMin).fold<int>(18 * 60, (a, b) => a > b ? a : b);
    return WeekGridLayout(startHour: minStart ~/ 60, endHour: (maxEnd + 59) ~/ 60, hourHeight: hourHeight);
  }

  /// The grid's height, from the first hour line to the last.
  double get height => (endHour - startHour) * hourHeight;

  /// How far down the line of [hour] is.
  double hourTop(int hour) => (hour - startHour) * hourHeight;

  /// How far down [minute] (minutes after midnight) is.
  double minuteTop(int minute) => (minute - startHour * 60) / 60 * hourHeight;

  /// Whether [minute] falls within the hours shown.
  bool shows(int minute) => minute >= startHour * 60 && minute <= endHour * 60;

  /// A class's block height: at least 40 px, so a short class is still easy
  /// to tap.
  double blockHeight(ClassSession s) => ((s.endMin - s.startMin) / 60 * hourHeight - 2).clamp(40.0, double.infinity);

  /// Lays out one day's sessions side by side where they overlap in time.
  static List<PlacedSession> placeDay(List<ClassSession> sessions) {
    final sorted = [...sessions]..sort((a, b) => a.startMin.compareTo(b.startMin));
    final placed = <PlacedSession>[];

    var cluster = <ClassSession>[];
    var clusterEnd = 0;

    void flush() {
      final laneEnds = <int>[];
      final lanes = <int>[];
      for (final s in cluster) {
        var lane = laneEnds.indexWhere((end) => end <= s.startMin);
        if (lane == -1) {
          laneEnds.add(s.endMin);
          lane = laneEnds.length - 1;
        } else {
          laneEnds[lane] = s.endMin;
        }
        lanes.add(lane);
      }
      for (var i = 0; i < cluster.length; i++) {
        placed.add(PlacedSession(cluster[i], lanes[i], laneEnds.length));
      }
      cluster = [];
    }

    for (final s in sorted) {
      if (cluster.isNotEmpty && s.startMin >= clusterEnd) flush();
      cluster.add(s);
      clusterEnd = cluster.length == 1 ? s.endMin : (s.endMin > clusterEnd ? s.endMin : clusterEnd);
    }
    if (cluster.isNotEmpty) flush();
    return placed;
  }
}
