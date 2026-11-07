import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/peoplesoft.dart';
import 'package:resit/core/network/session_client.dart';

/// One class meeting on a specific date.
class ClassSession {
  final DateTime date; // date only
  final String courseCode; // e.g. "CSC 2101"
  final String section; // e.g. "L1", "P2", "ALL"
  final String component; // Lectorial, Laboratory, ...
  final int startMin;
  final int endMin;
  final String location;

  /// ADFS/in4sit flags this when another class overlaps in time.
  final bool coinciding;

  ClassSession({
    required this.date,
    required this.courseCode,
    required this.section,
    required this.component,
    required this.startMin,
    required this.endMin,
    required this.location,
    required this.coinciding,
  });

  static String formatMinutes(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String get timeLabel => '${formatMinutes(startMin)} - ${formatMinutes(endMin)}';
}

class WeekSchedule {
  final DateTime monday;
  final List<ClassSession> sessions;

  WeekSchedule(this.monday, this.sessions);

  List<ClassSession> forDay(int dayIndex) => sessions
      .where((s) => s.date == DateTime(monday.year, monday.month, monday.day + dayIndex))
      .toList();
}

/// Reads the "My Class Schedule > Weekly Calendar View" page of in4sit. The
/// page is stateful on the server (PeopleSoft), so requests go through the
/// app's one [In4SitQueue] and the form state is carried from one response
/// to the next.
class TimetableService {
  final AuthService auth;

  /// Shared with every other in4SIT reader, so their requests take turns.
  final In4SitQueue queue;

  TimetableService(this.auth, {In4SitQueue? queue}) : queue = queue ?? In4SitQueue();

  static const String pageUrl =
      "https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/SA_LEARNER_SERVICES.SSR_SSENRL_SCHD_W.GBL";

  static const String _refreshAction = r'DERIVED_CLASS_S_SSR_REFRESH_CAL$8$';
  static const String _startDateField = 'DERIVED_CLASS_S_START_DT';

  late final PeopleSoftPage _page = PeopleSoftPage(auth, Uri.parse(pageUrl), queue: queue);
  WeekSchedule? _current;

  /// The schedule for the week starting on [monday].
  Future<WeekSchedule> week(
    DateTime monday, {
    void Function(MfaChallenge challenge)? onMfaChallenge,
  }) {
    Future<WeekSchedule> load() async {
      final shown = _current;
      if (shown != null && shown.monday == monday) return shown;

      // Not open yet, or another in4SIT page (e.g. exam results) was opened
      // since, which drops this page's state on the server.
      if (!_page.isOpen) await _open(onMfaChallenge);

      final current = _current;
      if (current != null && current.monday == monday) return current;

      _page.setField(_startDateField, DateFormat('dd/MM/yyyy').format(monday));
      final week = await _submit(_refreshAction);
      if (week.monday != monday) {
        debugLog('Timetable: asked for $monday but in4sit returned ${week.monday}');
      }
      return week;
    }

    return queue.run(() async {
      try {
        return await load();
      } on _PageLost {
        // in4SIT dropped the page we kept open: it does that after about 20
        // minutes idle, or when the same sign-in opens another in4SIT page.
        // Open it afresh and ask again, once, instead of showing an error.
        debugLog('Timetable: page state lost; reopening');
        reset();
        return await load();
      }
    });
  }

  /// Forgets the server-side page state so the next call starts afresh.
  void reset() {
    _current = null;
    _page.close();
  }

  Future<void> _open(void Function(MfaChallenge)? onMfaChallenge) async {
    reset();
    final ({String body, TimetableReply data}) opened;
    try {
      opened = await _page.openWith(readTimetableReply, onMfaChallenge: onMfaChallenge);
    } on In4SitHttpException catch (e) {
      throw Exception('Failed to load timetable: ${e.statusCode}');
    }
    debugLog('Timetable open: ${opened.body.length} chars');
    var week = opened.data.week;

    // The page remembers the last display option; make sure it is the calendar.
    final weekly = opened.data.weeklyRadio;
    if (weekly != null && !weekly.checked) {
      _page.setField(weekly.name, 'W');
      week = await _submit(weekly.id);
    }

    if (week == null) {
      debugLog('Timetable: no weekly grid found. First 500 chars:');
      debugLog(opened.body.substring(0, opened.body.length.clamp(0, 500)));
      reset();
      throw Exception('in4sit did not return the weekly schedule.');
    }
    _current = week;
  }

  /// Presses a button on the page and returns the resulting week.
  Future<WeekSchedule> _submit(String action) async {
    final ({String body, TimetableReply data}) reply;
    try {
      reply = await _page.pressWith(action, readTimetableReply);
    } on In4SitHttpException {
      reset();
      throw const _PageLost();
    }
    final week = reply.data.week;
    if (week == null) {
      final start = reply.body.substring(0, reply.body.length.clamp(0, 600)).replaceAll(RegExp(r'\s+'), ' ');
      debugLog('Timetable: no week in the reply. Starts: ${start.substring(0, start.length.clamp(0, 300))}');
      // Start over on the next call.
      reset();
      throw const _PageLost();
    }
    _current = week;
    return week;
  }
}

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

/// in4SIT answered without the weekly grid: the page state we kept is gone.
class _PageLost implements Exception {
  const _PageLost();

  @override
  String toString() => "in4SIT didn't send this week's timetable. Try again in a moment.";
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
