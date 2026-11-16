import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/sites/in4sit/peoplesoft_parsers.dart';
import 'package:resit/features/timetable/domain/class_session.dart';

// Reading in4SIT's "Weekly Calendar View" page into the app's models: the
// week's grid of classes, and the display option the page was left on.

/// What the timetable needs from one in4SIT reply.
class TimetableReply {
  /// The week shown, or null if the reply has no weekly grid.
  final WeekSchedule? week;

  /// The "Weekly Calendar View" display option, if the page has it.
  final ({String name, String id, bool checked})? weeklyRadio;

  const TimetableReply(this.week, this.weeklyRadio);
}

const _formatFieldPrefix = 'DERIVED_REGFRM1_SSR_SCHED_FORMAT';

/// Reads a parsed timetable reply: the week and the display option. Pure,
/// so it can run on a background isolate.
TimetableReply readTimetableReply(dom.Document doc, String html) {
  final radio = doc
      .querySelectorAll('input[type="radio"]')
      .where((i) => (i.attributes['name'] ?? '').startsWith(_formatFieldPrefix) && i.attributes['value'] == 'W')
      .firstOrNull;
  final name = radio?.attributes['name'];
  return TimetableReply(
    parseWeekDoc(doc, html),
    radio == null || name == null
        ? null
        : (name: name, id: radio.attributes['id'] ?? name, checked: radio.attributes.containsKey('checked')),
  );
}

/// Parses the weekly calendar grid, or returns null if the page has none.
WeekSchedule? parseWeek(String body) {
  final html = unwrapPeopleSoft(body);
  return parseWeekDoc(parser.parse(html), html);
}

// "Week of 5/10/2026 - 11/10/2026", allowing for tags and &nbsp; between.
final _weekOf = RegExp(r'Week of(?:\s|&nbsp;|&#160;|\u00a0|<[^>]*>)+(\d{1,2})/(\d{1,2})/(\d{4})');

/// [parseWeek] for an already parsed page; [html] is the HTML it came from.
WeekSchedule? parseWeekDoc(dom.Document doc, String html) {
  final table = doc.getElementById('WEEKLY_SCHED_HTMLAREA');
  if (table == null) return null;

  final label = _weekOf.firstMatch(html);
  if (label == null) return null;
  final monday = DateTime(int.parse(label.group(3)!), int.parse(label.group(2)!), int.parse(label.group(1)!));

  final sessions = <String, ClassSession>{};

  // Lay the table out the way a browser does: a cell with rowspan > 1 keeps
  // its column occupied in the rows below, which shifts the cells after it.
  final remaining = List<int>.filled(8, 0);
  final rows = table.querySelectorAll('tr');
  for (final tr in rows.skip(1)) {
    final started = <int, int>{};
    var col = 0;
    for (final cell in tr.children.where((c) => c.localName == 'td' || c.localName == 'th')) {
      while (col < 8 && remaining[col] > 0) {
        col++;
      }
      if (col >= 8) break;

      final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
      if (rowspan > 1) started[col] = rowspan - 1;

      if (col >= 1) {
        final date = DateTime(monday.year, monday.month, monday.day + col - 1);
        for (final s in _parseCell(cell, date)) {
          sessions['${s.date}|${s.courseCode}|${s.section}|${s.component}|${s.startMin}|${s.endMin}'] = s;
        }
      }
      col++;
    }
    for (var c = 0; c < 8; c++) {
      if (remaining[c] > 0) remaining[c]--;
    }
    started.forEach((c, v) => remaining[c] = v);
  }

  final list = sessions.values.toList()
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.startMin.compareTo(b.startMin);
    });
  return WeekSchedule(monday, list);
}

/// A cell holds one class as lines separated by <br>:
///   "CSC 2101 - L1", "Lectorial", "9:00AM - 11:00AM", "Online"
/// Overlapping classes are stacked in one cell, separated by a warning icon.
List<ClassSession> _parseCell(dom.Element cell, DateTime date) {
  final groups = <List<String>>[[]];
  void walk(dom.Node node) {
    if (node is dom.Text) {
      final t = node.text.trim();
      if (t.isNotEmpty) groups.last.add(t);
    } else if (node is dom.Element) {
      if (node.localName == 'img') {
        groups.add([]);
      } else {
        node.nodes.forEach(walk);
      }
    }
  }

  cell.nodes.forEach(walk);

  final result = <ClassSession>[];
  final coinciding = groups.where((g) => g.isNotEmpty).length > 1;
  for (final lines in groups) {
    if (lines.length < 3) continue;
    final codeMatch = RegExp(r'^(.+?)\s+-\s+(\S+)$').firstMatch(lines[0]);
    final range = _parseTimeRange(lines[2]);
    if (codeMatch == null || range == null) continue;

    result.add(ClassSession(
      date: date,
      courseCode: codeMatch.group(1)!,
      section: codeMatch.group(2)!,
      component: lines[1],
      startMin: range.$1,
      endMin: range.$2,
      location: lines.skip(3).join(' '),
      coinciding: coinciding,
    ));
  }
  return result;
}

/// "9:00AM - 11:00AM" -> (540, 660)
(int, int)? _parseTimeRange(String text) {
  final matches = RegExp(r'(\d{1,2}):(\d{2})\s*([AP]M)', caseSensitive: false).allMatches(text).toList();
  if (matches.length < 2) return null;

  int toMinutes(RegExpMatch m) {
    var hour = int.parse(m.group(1)!) % 12;
    if (m.group(3)!.toUpperCase() == 'PM') hour += 12;
    return hour * 60 + int.parse(m.group(2)!);
  }

  return (toMinutes(matches[0]), toMinutes(matches[1]));
}
