import 'dart:async';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';
import 'package:resit/core/auth/auth_service.dart';
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
/// page is stateful on the server (PeopleSoft), so requests are serialised and
/// the form state is carried from one response to the next.
class TimetableService {
  final AuthService auth;

  TimetableService(this.auth);

  static const String pageUrl =
      "https://in4sit.singaporetech.edu.sg/psc/CSSISSTD/EMPLOYEE/SA/c/SA_LEARNER_SERVICES.SSR_SSENRL_SCHD_W.GBL";

  static const String _refreshAction = r'DERIVED_CLASS_S_SSR_REFRESH_CAL$8$';
  static const String _startDateField = 'DERIVED_CLASS_S_START_DT';
  static const String _formatFieldPrefix = 'DERIVED_REGFRM1_SSR_SCHED_FORMAT';

  Map<String, String> _form = {};
  WeekSchedule? _current;
  bool _ready = false;
  Future<void> _tail = Future.value();

  /// The schedule for the week starting on [monday].
  Future<WeekSchedule> week(
    DateTime monday, {
    void Function(MfaChallenge challenge)? onMfaChallenge,
  }) {
    Future<WeekSchedule> load() async {
      if (!_ready) await _open(onMfaChallenge);

      final current = _current;
      if (current != null && current.monday == monday) return current;

      _form[_startDateField] = DateFormat('dd/MM/yyyy').format(monday);
      final week = await _submit(_refreshAction);
      if (week.monday != monday) {
        debugLog('Timetable: asked for $monday but in4sit returned ${week.monday}');
      }
      return week;
    }

    return _serial(() async {
      try {
        return await load();
      } on _PageLost {
        // in4SIT dropped the page we kept open: it does that after about 20
        // minutes idle, or when the same sign-in opens another in4SIT page
        // (e.g. exam results being read in the background). Open it afresh
        // and ask again, once, instead of showing an error.
        debugLog('Timetable: page state lost; reopening');
        reset();
        return await load();
      }
    });
  }

  /// Forgets the server-side page state so the next call starts afresh.
  void reset() {
    _ready = false;
    _current = null;
    _form = {};
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<void> _open(void Function(MfaChallenge)? onMfaChallenge) async {
    reset();
    final target = Uri.parse(pageUrl);
    final response = await auth.getWithSso(target, onMfaChallenge: onMfaChallenge);
    debugLog('Timetable open: status ${response.statusCode}, URL: ${response.request?.url}');

    // Still on ADFS (or anywhere but in4sit) means SSO could not sign us in.
    final landed = response.request?.url;
    if (landed != null && landed.host != target.host) {
      final doc = parser.parse(response.body);
      final title = doc.querySelector('title')?.text.trim() ?? '';
      final hasPassword = doc.querySelector('input[type="password"]') != null;
      throw SessionExpiredException(
          'Landed on ${landed.host}${landed.path}'
          '${title.isNotEmpty ? ' ("$title")' : ''}'
          '${hasPassword ? ', which is asking for a password' : ''}.');
    }
    if (response.statusCode >= 400) {
      throw Exception('Failed to load timetable: ${response.statusCode}');
    }

    final doc = parser.parse(_unwrapFields(response.body));
    _form = _collectForm(doc);
    var week = parseWeek(response.body);

    // The page remembers the last display option; make sure it is the calendar.
    final weekly = doc
        .querySelectorAll('input[type="radio"]')
        .where((i) => (i.attributes['name'] ?? '').startsWith(_formatFieldPrefix) && i.attributes['value'] == 'W')
        .firstOrNull;
    if (weekly != null && !weekly.attributes.containsKey('checked')) {
      _form[weekly.attributes['name']!] = 'W';
      _ready = true;
      week = await _submit(weekly.attributes['id'] ?? weekly.attributes['name']!);
    }

    if (week == null) {
      debugLog('Timetable: no weekly grid found. First 500 chars:');
      debugLog(response.body.substring(0, response.body.length.clamp(0, 500)));
      throw Exception('in4sit did not return the weekly schedule.');
    }
    _current = week;
    _ready = true;
  }

  /// Presses a button on the page and returns the resulting week.
  Future<WeekSchedule> _submit(String action) async {
    final body = Map<String, String>.from(_form)
      ..['ICAJAX'] = '1'
      ..['ICNAVTYPEDROPDOWN'] = '0'
      ..['ICChanged'] = '1'
      ..['ICAction'] = action;

    final response = await auth.client.post(
      Uri.parse(pageUrl),
      headers: {
        'x-requested-with': 'XMLHttpRequest',
        'referer': pageUrl,
        'origin': 'https://in4sit.singaporetech.edu.sg',
      },
      body: body,
    );
    debugLog('Timetable submit $action: status ${response.statusCode}, ${response.body.length} chars');

    final week = response.statusCode == 200 ? parseWeek(response.body) : null;
    if (week == null) {
      final start = response.body.replaceAll(RegExp(r'\s+'), ' ');
      debugLog('Timetable: no week in the reply. Starts: ${start.substring(0, start.length.clamp(0, 300))}');
      // Start over on the next call.
      reset();
      throw const _PageLost();
    }

    _absorb(response.body);
    _current = week;
    return week;
  }

  /// Everything a browser would submit for the page's form.
  Map<String, String> _collectForm(dom.Document doc) {
    final form = doc.querySelector('form[name="win0"]') ?? doc.querySelector('form#win0');
    final scope = form ?? doc.documentElement!;
    final fields = <String, String>{};
    _readInputs(scope, fields);
    fields['ICAction'] = 'None';
    return fields;
  }

  void _readInputs(dom.Element scope, Map<String, String> fields) {
    for (final el in scope.querySelectorAll('input, select, textarea')) {
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;

      if (el.localName == 'select') {
        final selected = el.querySelector('option[selected]') ?? el.querySelector('option');
        fields[name] = selected?.attributes['value'] ?? selected?.text ?? '';
      } else if (el.localName == 'textarea') {
        fields[name] = el.text;
      } else {
        final type = (el.attributes['type'] ?? 'text').toLowerCase();
        switch (type) {
          case 'button':
          case 'submit':
          case 'image':
          case 'reset':
            break;
          case 'checkbox':
            if (el.attributes.containsKey('checked')) {
              fields[name] = el.attributes['value'] ?? 'on';
            } else {
              fields.remove(name);
            }
          case 'radio':
            if (el.attributes.containsKey('checked')) fields[name] = el.attributes['value'] ?? '';
          default:
            fields[name] = el.attributes['value'] ?? '';
        }
      }
    }
  }

  /// Carries the page state forward from an AJAX response: new field values
  /// and the server's state counter (which must match on the next request).
  void _absorb(String body) {
    final doc = parser.parse(_unwrapFields(body));
    _readInputs(doc.documentElement!, _form);

    final state = RegExp(r'ICStateNum\.value\s*=\s*(\d+)').firstMatch(body);
    if (state != null) {
      _form['ICStateNum'] = state.group(1)!;
    } else {
      _form['ICStateNum'] = '${(int.tryParse(_form['ICStateNum'] ?? '') ?? 0) + 1}';
    }
    _form['ICAction'] = 'None';
    _form['ICResubmit'] = '0';
  }
}

/// in4SIT answered without the weekly grid: the page state we kept is gone.
class _PageLost implements Exception {
  const _PageLost();

  @override
  String toString() => "in4SIT didn't send this week's timetable. Try again in a moment.";
}

/// PeopleSoft answers ICAJAX requests with XML whose <FIELD> elements wrap the
/// real HTML in CDATA; a normal page load is plain HTML. Handle both.
String _unwrapFields(String body) {
  if (!body.contains('<![CDATA[')) return body;
  final buf = StringBuffer();
  final re = RegExp(r'<FIELD\b[^>]*><!\[CDATA\[(.*?)\]\]></FIELD>', dotAll: true, caseSensitive: false);
  for (final m in re.allMatches(body)) {
    buf.write(m.group(1));
  }
  return buf.isEmpty ? body : buf.toString();
}

/// Parses the weekly calendar grid, or returns null if the page has none.
WeekSchedule? parseWeek(String body) {
  final doc = parser.parse(_unwrapFields(body));
  final table = doc.getElementById('WEEKLY_SCHED_HTMLAREA');
  if (table == null) return null;

  // "Week of 5/10/2026 - 11/10/2026"
  final text = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
  final label = RegExp(r'Week of\s+(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(text);
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
