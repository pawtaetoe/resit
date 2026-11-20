import 'dart:convert';
import 'dart:typed_data';

import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/sites/xsite/results_service.dart';
import 'package:resit/sites/xsite/xsite_client.dart';
import 'package:resit/sites/xsite/activity_parsers.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';
import 'package:resit/sites/xsite/course_parsers.dart';
import 'package:resit/sites/xsite/discussions_service.dart';

export 'package:resit/sites/xsite/lms_unavailable_exception.dart' show LmsUnavailableException;

/// Reads xSiTe with the same SIT single sign-on as in4SIT: xSiTe hands off
/// to SIT's ADFS, which already knows the user, and back.
class LmsService {
  static const base = xsiteBase;

  /// Resolves a link from an xSiTe reply against xSiTe, and refuses one that
  /// points anywhere else: the app only ever fetches from xSiTe itself.
  static Uri onXsite(String link) {
    final uri = Uri.parse(base).resolve(link);
    if (uri.scheme != 'https' || uri.host != Uri.parse(base).host) {
      throw FormatException('Ignored a link from xSiTe that leaves xSiTe: ${uri.scheme}://${uri.host}');
    }
    return uri;
  }

  /// The list the "My Courses" widget on xSiTe's home page shows.
  static Uri myCoursesUrl({String? bookmark}) => Uri.parse('$base/d2l/le/manageCourses/api/mycourses').replace(
        queryParameters: {
          'pageSize': '20',
          'sort': 'current',
          'autoPinCourses': 'false',
          'orgUnitTypeId': '3',
          'promotePins': 'true',
          'embedDepth': '0',
          'widgetId': '49',
          'parentOrgUnitIds': '188630',
          if (bookmark != null) 'bookmark': bookmark,
        },
      );

  final AuthService auth;
  final Map<String, Future<Uint8List?>> _images = {};

  /// How long the course list is reused before xSiTe is asked again.
  static const coursesTtl = Duration(minutes: 10);

  /// Requests (progress, contents, images) in flight at once, at most.
  static const maxInFlight = 4;

  final DateTime Function() _now;
  ({DateTime at, List<LmsCourse> courses})? _courses;
  Future<List<LmsCourse>>? _coursesInFlight;
  final XsiteClient _xsite;

  LmsService(this.auth, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _xsite = XsiteClient(auth, maxInFlight: maxInFlight);

  /// Course discussions (forums, topics, posts), read only.
  late final discussions = XsiteDiscussions(_xsite);

  /// Every course on xSiTe, signing in to xSiTe first if needed. Reused for
  /// [coursesTtl]; [force] asks xSiTe again.
  Future<List<LmsCourse>> courses({void Function(MfaChallenge)? onMfaChallenge, bool force = false}) {
    final kept = _courses;
    if (!force && kept != null && _now().difference(kept.at) < coursesTtl) return Future.value(List.of(kept.courses));
    if (!force && _coursesInFlight != null) return _coursesInFlight!.then(List.of);
    final future = _fetchCourses(onMfaChallenge);
    _coursesInFlight = future;
    future.then((c) => _courses = (at: _now(), courses: c), onError: (_) {}).whenComplete(() {
      if (identical(_coursesInFlight, future)) _coursesInFlight = null;
    });
    return future.then(List.of);
  }

  /// Forgets the course list, e.g. after signing out.
  void clearCache() {
    _courses = null;
    _coursesInFlight = null;
    _images.clear();
    _myId = null;
  }

  Future<List<LmsCourse>> _fetchCourses(void Function(MfaChallenge)? onMfaChallenge) async {
    final all = <String, LmsCourse>{};
    String? bookmark;
    // A few pages at most; stop if a page adds nothing new.
    for (var page = 0; page < 5; page++) {
      final body = await _xsite.getJson(myCoursesUrl(bookmark: bookmark), onMfaChallenge);
      final json = jsonDecode(stripGuard(body));
      final before = all.length;
      for (final c in parseMyCourses(body)) {
        all[c.orgUnitId] = c;
      }
      final next = json is Map ? json['Bookmark'] : null;
      if (next == null || '$next'.isEmpty || all.length == before) break;
      bookmark = '$next';
    }
    return sortCourses(all.values);
  }

  /// Which of the course's content items the user has completed.
  Future<CourseProgress> progress(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final items = <ContentItem>[];
    Uri? url = Uri.parse('$base/d2l/api/le/1.75/$orgUnitId/content/completions/mycount/?level=3');
    for (var page = 0; page < 10 && url != null; page++) {
      final parsed = parseCompletions(await _xsite.getJson(url, onMfaChallenge, limited: true));
      items.addAll(parsed.items);
      final next = parsed.next;
      url = next == null ? null : onXsite(next);
    }
    return CourseProgress(items);
  }

  /// The course's content, folder by folder.
  Future<List<ContentModule>> contents(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final url = Uri.parse('$base/d2l/api/le/1.75/$orgUnitId/content/toc');
    return parseToc(orgUnitId, await _xsite.getJson(url, onMfaChallenge, limited: true));
  }

  // --- Course activities (announcements, assignments, quizzes, grades, groups)

  static const _le = '$base/d2l/api/le/1.75';
  static const _lp = '$base/d2l/api/lp/1.47';

  Future<String> _api(String url, void Function(MfaChallenge)? onMfaChallenge) =>
      _xsite.getJson(Uri.parse(url), onMfaChallenge, limited: true);

  /// A course's announcements, newest first.
  Future<List<Announcement>> announcements(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async =>
      parseAnnouncements(await _api('$_le/$orgUnitId/news/', onMfaChallenge));

  /// A course's assignments (dropbox folders), soonest deadline first, each
  /// with when you submitted (if you did). A folder whose submissions can't
  /// be read keeps `submissions == null`.
  Future<List<Assignment>> assignments(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final folders = parseAssignments(orgUnitId, await _api('$_le/$orgUnitId/dropbox/folders/', onMfaChallenge));
    return Future.wait([
      for (final f in folders)
        _api('$_le/$orgUnitId/dropbox/folders/${f.id}/submissions/mysubmissions/', onMfaChallenge)
            .then((b) => f.withSubmissions(parseMySubmissions(b)))
            .catchError((Object _) => f),
    ]);
  }

  /// A course's quizzes, soonest deadline first.
  Future<List<Quiz>> quizzes(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final all = <Quiz>[];
    String? url = '$_le/$orgUnitId/quizzes/';
    for (var page = 0; page < 10 && url != null; page++) {
      final parsed = parseQuizzes(orgUnitId, await _api(url, onMfaChallenge));
      all.addAll(parsed.quizzes);
      final next = parsed.next;
      url = next == null ? null : onXsite(next).toString();
    }
    return sortQuizzes(all);
  }

  /// Your released grades in a course, and the final grade if released.
  Future<CourseGrades> grades(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final items = parseGrades(await _api('$_le/$orgUnitId/grades/values/myGradeValues/', onMfaChallenge));
    GradeEntry? finalGrade;
    try {
      finalGrade = parseFinalGrade(await _api('$_le/$orgUnitId/grades/final/values/myGradeValue', onMfaChallenge));
    } catch (_) {
      // Not released yet (xSiTe answers 404).
    }
    return CourseGrades(items, finalGrade);
  }

  String? _myId;

  /// Your xSiTe user id, asked once until signed out.
  Future<String> _whoAmI(void Function(MfaChallenge)? onMfaChallenge) async =>
      _myId ??= parseWhoAmI(await _api('$_lp/users/whoami', onMfaChallenge));

  late final _results = XsiteResults(_xsite, myId: _whoAmI);

  /// Your released feedback on an assignment, or null (see [XsiteResults.feedback]).
  Future<AssignmentFeedback?> feedback(Assignment a, {void Function(MfaChallenge)? onMfaChallenge}) =>
      _results.feedback(a, onMfaChallenge: onMfaChallenge);

  /// Your attempts at a quiz (see [XsiteResults.quizAttempts]).
  Future<List<QuizAttempt>> quizAttempts(Quiz q, {void Function(MfaChallenge)? onMfaChallenge}) =>
      _results.quizAttempts(q, onMfaChallenge: onMfaChallenge);

  /// The groups you're in for a course, with members' names when the class
  /// list can be read.
  Future<List<MyGroup>> groups(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    // Who you are and the course's categories at the same time, then every
    // category's groups at once (the limiter keeps it to a few requests).
    final meFuture = _myId != null ? Future.value('') : _api('$_lp/users/whoami', onMfaChallenge);
    final categoriesFuture = _api('$_lp/$orgUnitId/groupcategories/', onMfaChallenge);
    await Future.wait([meFuture, categoriesFuture]);
    final meBody = await meFuture, categoriesBody = await categoriesFuture;
    final me = _myId ??= parseWhoAmI(meBody);
    final categories = parseGroupCategories(categoriesBody);
    final perCategory = await Future.wait([
      for (final c in categories)
        _api('$_lp/$orgUnitId/groupcategories/${c.id}/groups/', onMfaChallenge).then((b) => (c.name, parseGroups(b))),
    ]);
    final found = [
      for (final (category, groups) in perCategory)
        for (final g in groups)
          if (g.members.contains(me)) (category, g),
    ];
    var names = const <String, String>{};
    if (found.isNotEmpty) {
      try {
        names = parseClasslist(await _api('$_le/$orgUnitId/classlist/', onMfaChallenge));
      } catch (_) {
        // The class list may be closed to students: members show as a count.
      }
    }
    return [
      for (final (category, g) in found)
        MyGroup(
          category: category,
          name: g.name,
          description: g.description,
          memberCount: g.members.length,
          members: [
            for (final id in g.members)
              if (names[id] case final name?) GroupMember(id, id == me ? '$name (you)' : name),
          ],
        ),
    ];
  }

  /// The course's picture, about [size] pixels across (the list shows it
  /// at 56 dp, so 168 px covers a 3× screen), or null if it has none or
  /// can't be read. Kept for the app's lifetime.
  Future<Uint8List?> image(LmsCourse course, {int size = 168}) {
    final path = course.imagePath;
    if (path == null) return Future.value(null);
    return _images.putIfAbsent(course.orgUnitId, () async {
      try {
        final uri = onXsite(path);
        final sized = uri.replace(queryParameters: {...uri.queryParameters, 'width': '$size', 'height': '$size'});
        final resp = await _xsite.getLimited(sized);
        final type = resp.headers['content-type'] ?? '';
        if (resp.statusCode != 200 || !type.startsWith('image/')) return null;
        return resp.bodyBytes;
      } catch (_) {
        return null;
      }
    });
  }
}
