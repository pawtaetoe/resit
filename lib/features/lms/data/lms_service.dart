import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';

/// One course on xSiTe (SIT's Brightspace LMS).
class LmsCourse {
  final String orgUnitId;

  /// As xSiTe names it: "INF2004-Embedded Systems Programming [2026/27 T1]".
  final String name;

  /// e.g. "SIT-2610-INF2004".
  final String code;

  /// e.g. "2026/27 Trimester 1".
  final String semester;
  final DateTime? start;
  final DateTime? end;
  final bool isActive;
  final bool canAccess;
  final DateTime? lastAccessed;

  /// Relative path of the course image, if it has one.
  final String? imagePath;

  LmsCourse({
    required this.orgUnitId,
    required this.name,
    required this.code,
    required this.semester,
    this.start,
    this.end,
    this.isActive = true,
    this.canAccess = true,
    this.lastAccessed,
    this.imagePath,
  });

  static final _nameParts = RegExp(r'^([A-Z]{2,4}\d{3,4}[A-Z]?)\s*-\s*(.+?)(?:\s*\[([^\]]+)\])?$');

  /// "INF2004", or the last part of [code] if the name doesn't start with one.
  String get courseCode => _nameParts.firstMatch(name)?.group(1) ?? code.split('-').last;

  /// "Embedded Systems Programming", without the code and the term.
  String get title {
    final m = _nameParts.firstMatch(name);
    if (m == null) return name;
    return m.group(2)!.trim();
  }

  /// "2026/27 T1" from the name, or the semester as xSiTe gives it.
  String get termLabel => _nameParts.firstMatch(name)?.group(3) ?? semester;

  /// The course's home page on xSiTe.
  Uri get homeUrl => Uri.parse('${LmsService.base}/d2l/home/$orgUnitId');

  factory LmsCourse.fromJson(Map<String, Object?> j) {
    DateTime? date(String key) {
      final v = j[key];
      return v is String ? DateTime.tryParse(v)?.toLocal() : null;
    }

    final image = j['FormattedImageLink'];
    return LmsCourse(
      orgUnitId: '${j['OrgUnitId']}',
      name: (j['Name'] as String? ?? '').trim(),
      code: j['Code'] as String? ?? '',
      semester: j['SemesterName'] as String? ?? '',
      start: date('StartDate'),
      end: date('EndDate'),
      isActive: j['IsActive'] as bool? ?? true,
      canAccess: j['CanAccessCourse'] as bool? ?? true,
      lastAccessed: date('LastAccessed'),
      imagePath: image is String && image.isNotEmpty ? image : null,
    );
  }
}

/// One item in a course's content (a file, link, video, ...) and whether the
/// user has completed it.
class ContentItem {
  final String orgUnitId;
  final int objectId;
  final String title;
  final int required;
  final int completed;

  ContentItem({
    required this.orgUnitId,
    required this.objectId,
    required this.title,
    required this.required,
    required this.completed,
  });

  bool get done => completed >= required;

  /// The item on xSiTe.
  Uri get url => Uri.parse('${LmsService.base}/d2l/le/content/$orgUnitId/viewContent/$objectId/View');

  factory ContentItem.fromJson(Map<String, Object?> j) => ContentItem(
        orgUnitId: '${j['OrgUnitId']}',
        objectId: (j['ObjectId'] as num?)?.toInt() ?? 0,
        title: (j['Title'] as String? ?? '').trim(),
        required: (j['RequiredItems'] as num?)?.toInt() ?? 0,
        completed: (j['CompletedItems'] as num?)?.toInt() ?? 0,
      );
}

/// How far through a course's content the user is.
class CourseProgress {
  final List<ContentItem> items;
  CourseProgress(this.items);

  int get required => items.fold(0, (a, i) => a + i.required);
  int get completed => items.fold(0, (a, i) => a + (i.completed > i.required ? i.required : i.completed));
  double get fraction => required == 0 ? 0 : completed / required;
  List<ContentItem> get todo => [for (final i in items) if (!i.done) i];
  List<ContentItem> get done => [for (final i in items) if (i.done) i];
}

/// The items in one page of xSiTe's completion counts, and the next page's
/// address (null on the last page).
({List<ContentItem> items, String? next}) parseCompletions(String body) {
  final json = jsonDecode(_stripGuard(body));
  final list = (json is Map ? json['Objects'] : null) as List? ?? const [];
  final next = json is Map ? json['Next'] : null;
  return (
    items: [
      for (final o in list)
        if (o is Map) ContentItem.fromJson(o.cast<String, Object?>()),
    ],
    next: next is String && next.isNotEmpty ? next : null,
  );
}

/// One item in a course's content: a file, link, video, ...
class ContentTopic {
  final String orgUnitId;
  final int id;
  final String title;

  /// "File", "Link", "ContentService" (a video), ...
  final String type;

  /// Where it points: a web address for links, a path on xSiTe for files.
  final String url;
  final bool unread;
  final String description;

  ContentTopic({
    required this.orgUnitId,
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    this.unread = false,
    this.description = '',
  });

  bool get isLink => type == 'Link' && (url.startsWith('https://') || url.startsWith('http://'));

  /// The file's extension in lower case ("pdf", "mp4", ...), if it's a file.
  String get extension {
    if (type != 'File') return '';
    final dot = url.lastIndexOf('.');
    return dot < 0 ? '' : url.substring(dot + 1).toLowerCase();
  }

  /// Where to open it: a link's own address, otherwise its page on xSiTe.
  Uri get openUrl =>
      isLink ? Uri.parse(url) : Uri.parse('${LmsService.base}/d2l/le/content/$orgUnitId/viewContent/$id/View');

  static ContentTopic? fromJson(String orgUnitId, Map<String, Object?> j) {
    if (j['IsHidden'] == true) return null;
    final description = j['Description'];
    return ContentTopic(
      orgUnitId: orgUnitId,
      id: (j['TopicId'] as num?)?.toInt() ?? 0,
      title: (j['Title'] as String? ?? '').trim(),
      type: j['TypeIdentifier'] as String? ?? '',
      url: j['Url'] as String? ?? '',
      unread: j['Unread'] as bool? ?? false,
      description: description is Map ? (description['Text'] as String? ?? '').trim() : '',
    );
  }
}

/// A folder in a course's content, holding topics and more folders.
class ContentModule {
  final int id;
  final String title;
  final List<ContentModule> modules;
  final List<ContentTopic> topics;

  ContentModule({required this.id, required this.title, this.modules = const [], this.topics = const []});

  /// Every topic in this folder and the folders inside it.
  Iterable<ContentTopic> get allTopics sync* {
    yield* topics;
    for (final m in modules) {
      yield* m.allTopics;
    }
  }

  static ContentModule? fromJson(String orgUnitId, Map<String, Object?> j) {
    if (j['IsHidden'] == true) return null;
    int order(Object? o) => o is Map ? (o['SortOrder'] as num?)?.toInt() ?? 0 : 0;
    List<Map<String, Object?>> sorted(Object? list) =>
        [for (final o in (list as List? ?? const [])) if (o is Map) o.cast<String, Object?>()]
          ..sort((a, b) => order(a).compareTo(order(b)));
    return ContentModule(
      id: (j['ModuleId'] as num?)?.toInt() ?? 0,
      title: (j['Title'] as String? ?? '').trim(),
      modules: [
        for (final m in sorted(j['Modules']))
          if (ContentModule.fromJson(orgUnitId, m) case final module?) module,
      ],
      topics: [
        for (final t in sorted(j['Topics']))
          if (ContentTopic.fromJson(orgUnitId, t) case final topic?) topic,
      ],
    );
  }
}

/// A course's table of contents: its top-level folders, in course order.
List<ContentModule> parseToc(String orgUnitId, String body) {
  final json = jsonDecode(_stripGuard(body));
  final list = (json is Map ? json['Modules'] : null) as List? ?? const [];
  return ContentModule.fromJson(orgUnitId, {'Modules': list})?.modules ?? const [];
}

/// Courses from xSiTe's "My Courses" list, newest term first and, within a
/// term, the most recently opened first.
List<LmsCourse> parseMyCourses(String body) {
  final json = jsonDecode(_stripGuard(body));
  final list = (json is Map ? json['Courses'] : null) as List? ?? const [];
  return [
    for (final c in list)
      if (c is Map) LmsCourse.fromJson(c.cast<String, Object?>()),
  ];
}

/// Some Brightspace APIs put `while(1);` before JSON so it can't be loaded as
/// a script; drop it if present.
String _stripGuard(String body) {
  final t = body.trimLeft();
  return t.startsWith('while(1);') ? t.substring('while(1);'.length) : t;
}

/// Orders courses by term (newest first), then by when they were last
/// opened (most recent first), then by code.
List<LmsCourse> sortCourses(Iterable<LmsCourse> courses) {
  final list = courses.toList();
  list.sort((a, b) {
    final byStart = (b.start ?? DateTime(0)).compareTo(a.start ?? DateTime(0));
    if (byStart != 0) return byStart;
    final bySeen = (b.lastAccessed ?? DateTime(0)).compareTo(a.lastAccessed ?? DateTime(0));
    if (bySeen != 0) return bySeen;
    return a.courseCode.compareTo(b.courseCode);
  });
  return list;
}

/// Reads xSiTe with the same SIT single sign-on as in4SIT: xSiTe hands off
/// to SIT's ADFS, which already knows the user, and back.
class LmsService {
  static const base = 'https://xsite.singaporetech.edu.sg';

  /// Starts xSiTe's SIT sign-in (SAML via ADFS).
  static final samlLogin = Uri.parse('$base/d2l/lp/auth/saml/login?target=%2fd2l%2fhome');

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

  LmsService(this.auth);

  SessionClient get _client => auth.client;

  /// Every course on xSiTe, signing in to xSiTe first if needed.
  Future<List<LmsCourse>> courses({void Function(MfaChallenge)? onMfaChallenge}) async {
    final all = <String, LmsCourse>{};
    String? bookmark;
    // A few pages at most; stop if a page adds nothing new.
    for (var page = 0; page < 5; page++) {
      final body = await _getJson(myCoursesUrl(bookmark: bookmark), onMfaChallenge);
      final json = jsonDecode(_stripGuard(body));
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
      final parsed = parseCompletions(await _getJson(url, onMfaChallenge));
      items.addAll(parsed.items);
      final next = parsed.next;
      url = next == null ? null : Uri.parse(base).resolve(next);
    }
    return CourseProgress(items);
  }

  /// The course's content, folder by folder.
  Future<List<ContentModule>> contents(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final url = Uri.parse('$base/d2l/api/le/1.75/$orgUnitId/content/toc');
    return parseToc(orgUnitId, await _getJson(url, onMfaChallenge));
  }

  /// The course's picture (small), or null if it has none or can't be read.
  /// Kept for the app's lifetime.
  Future<Uint8List?> image(LmsCourse course) {
    final path = course.imagePath;
    if (path == null) return Future.value(null);
    return _images.putIfAbsent(course.orgUnitId, () async {
      try {
        final uri = Uri.parse(base).resolve(path);
        final sized = uri.replace(queryParameters: {...uri.queryParameters, 'width': '480', 'height': '180'});
        final resp = await _client.get(sized);
        final type = resp.headers['content-type'] ?? '';
        if (resp.statusCode != 200 || !type.startsWith('image/')) return null;
        return resp.bodyBytes;
      } catch (_) {
        return null;
      }
    });
  }

  /// GETs an xSiTe API; if xSiTe isn't signed in yet (it answers with its
  /// login page instead of JSON), signs in through ADFS and asks again.
  Future<String> _getJson(Uri url, void Function(MfaChallenge)? onMfaChallenge) async {
    var resp = await _client.get(url);
    if (_isJson(resp.statusCode, resp.headers, resp.body)) return resp.body;

    debugLog('xSiTe: not signed in (status ${resp.statusCode}, at ${resp.request?.url.path}); signing in');
    resp = await auth.getWithSso(samlLogin, thenGet: url, onMfaChallenge: onMfaChallenge);
    if (_isJson(resp.statusCode, resp.headers, resp.body)) return resp.body;

    final landed = resp.request?.url;
    throw SessionExpiredException(
        "xSiTe didn't sign in${landed == null ? '' : ' (ended on ${landed.host}${landed.path})'}.");
  }

  static bool _isJson(int status, Map<String, String> headers, String body) {
    if (status != 200) return false;
    final type = headers['content-type'] ?? '';
    final t = _stripGuard(body);
    return type.contains('json') || t.startsWith('{') || t.startsWith('[');
  }
}
