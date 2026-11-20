import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/updates.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/calendar_parsers.dart';
import 'package:resit/sites/xsite/xsite_client.dart';
import 'package:resit/sites/xsite/xsite_service.dart' show LmsService;

/// The student's xSiTe calendar and update counts across their courses
/// (read only).
class XsiteCalendar {
  static const _le = '$xsiteBase/d2l/api/le/1.75';

  /// Courses per request, at most (the routes' limit).
  static const perRequest = 100;

  final XsiteClient _xsite;
  XsiteCalendar(this._xsite);

  /// The address of the calendar events in [orgUnitIds] from [from] to [to].
  static Uri myEventsUrl(Iterable<String> orgUnitIds, DateTime from, DateTime to) =>
      Uri.parse('$_le/calendar/events/myEvents/').replace(queryParameters: {
        'orgUnitIdsCSV': orgUnitIds.join(','),
        'startDateTime': from.toUtc().toIso8601String(),
        'endDateTime': to.toUtc().toIso8601String(),
      });

  /// Every page of [first] and those after it (at most 10), each read by
  /// [parse]. Next-page links must stay on xSiTe.
  Future<void> _pages<T>(Uri first, ({T items, String? next}) Function(String) parse, void Function(T) add,
      void Function(MfaChallenge)? onMfaChallenge) async {
    Uri? url = first;
    for (var page = 0; page < 10 && url != null; page++) {
      final parsed = parse(await _xsite.getJson(url, onMfaChallenge, limited: true));
      add(parsed.items);
      final next = parsed.next;
      url = next == null ? null : LmsService.onXsite(next);
    }
  }

  /// [ids] in groups of [perRequest].
  static Iterable<List<String>> _chunks(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += perRequest) {
      yield ids.sublist(i, i + perRequest > ids.length ? ids.length : i + perRequest);
    }
  }

  /// Every event in [orgUnitIds]'s calendars from [from] to [to].
  Future<List<LmsEvent>> events(List<String> orgUnitIds, DateTime from, DateTime to,
      {void Function(MfaChallenge)? onMfaChallenge}) async {
    final all = <LmsEvent>[];
    for (final ids in _chunks(orgUnitIds)) {
      await _pages(myEventsUrl(ids, from, to), (b) {
        final p = parseMyEvents(b);
        return (items: p.events, next: p.next);
      }, all.addAll, onMfaChallenge);
    }
    return all;
  }

  /// Unread discussions, new feedback and quizzes to attempt for each of
  /// [orgUnitIds], by course id.
  Future<Map<String, CourseUpdates>> updates(List<String> orgUnitIds,
      {void Function(MfaChallenge)? onMfaChallenge}) async {
    final found = <String, CourseUpdates>{};
    for (final ids in _chunks(orgUnitIds)) {
      final url = Uri.parse('$_le/updates/myUpdates/').replace(queryParameters: {'orgUnitIdsCSV': ids.join(',')});
      await _pages(url, (b) {
        final p = parseMyUpdates(b);
        return (items: p.updates, next: p.next);
      }, found.addAll, onMfaChallenge);
    }
    return found;
  }

  /// The same counts for one course.
  Future<CourseUpdates> courseUpdates(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async =>
      parseCourseUpdates(
          await _xsite.getJson(Uri.parse('$_le/$orgUnitId/updates/myUpdates'), onMfaChallenge, limited: true));
}
