import 'package:intl/intl.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/peoplesoft.dart';
import 'package:resit/sites/in4sit/timetable_parsers.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/features/timetable/domain/class_session.dart';

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

/// in4SIT answered without the weekly grid: the page state we kept is gone.
class _PageLost implements Exception {
  const _PageLost();

  @override
  String toString() => "in4SIT didn't send this week's timetable. Try again in a moment.";
}
