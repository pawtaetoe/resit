import 'package:http/http.dart' as http;
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/course_extras_parsers.dart';
import 'package:resit/sites/xsite/xsite_client.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

/// Reads a course's overview, content files, checklists and surveys from
/// xSiTe. GET requests only, all to xSiTe through [XsiteClient] (signed in,
/// a few at a time).
class XsiteCourseExtras {
  static const _le = '$xsiteBase/d2l/api/le/1.75';

  /// A light JSON request that signs xSiTe in again when a file request
  /// found it signed out.
  static final _whoami = Uri.parse('$xsiteBase/d2l/api/lp/1.47/users/whoami');

  final XsiteClient _xsite;
  final DateTime Function() _now;

  XsiteCourseExtras(this._xsite, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<String> _get(String url, void Function(MfaChallenge)? onMfaChallenge) =>
      _xsite.getJson(Uri.parse(url), onMfaChallenge, limited: true);

  /// Every row of an ObjectListPage, following `Next` (on xSiTe only) for a
  /// few pages at most.
  Future<List<Map<String, Object?>>> _all(String url, void Function(MfaChallenge)? onMfaChallenge) async {
    final rows = <Map<String, Object?>>[];
    String? next = url;
    for (var page = 0; page < 10 && next != null; page++) {
      final parsed = parsePage(await _get(next, onMfaChallenge));
      rows.addAll(parsed.rows);
      next = parsed.next == null ? null : LmsService.onXsite(parsed.next!).toString();
    }
    return rows;
  }

  /// The course's overview, or null if it has none (xSiTe answers 404) or
  /// students can't read it.
  Future<CourseOverview?> overview(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    try {
      return parseOverview(await _get('$_le/$orgUnitId/overview', onMfaChallenge));
    } on LmsUnavailableException {
      return null;
    }
  }

  /// The overview's attached file.
  Future<XsiteFile> overviewAttachment(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) =>
      _file(Uri.parse('$_le/$orgUnitId/overview/attachment'), 'overview', onMfaChallenge);

  /// A file topic's file.
  Future<XsiteFile> topicFile(ContentTopic topic, {void Function(MfaChallenge)? onMfaChallenge}) {
    final fromUrl = Uri.tryParse(topic.url)?.pathSegments.lastOrNull ?? '';
    final fallback = fromUrl.isNotEmpty ? fromUrl : 'topic-${topic.id}${topic.extension.isEmpty ? '' : '.${topic.extension}'}';
    return _file(Uri.parse('$_le/${topic.orgUnitId}/content/topics/${topic.id}/file'), fallback, onMfaChallenge);
  }

  Future<XsiteFile> _file(Uri url, String fallbackName, void Function(MfaChallenge)? onMfaChallenge) async {
    var resp = await _xsite.getLimited(url);
    if (!_isFile(resp, url)) {
      // Most likely signed out (xSiTe answered with its login page): a JSON
      // request signs in again, then ask once more.
      await _xsite.getJson(_whoami, onMfaChallenge, limited: true);
      resp = await _xsite.getLimited(url);
    }
    if (!_isFile(resp, url)) throw LmsUnavailableException(url.path);
    return XsiteFile(
      name: downloadName(resp.headers['content-disposition'], safeFileName(fallbackName, 'file')),
      type: (resp.headers['content-type'] ?? '').split(';').first.trim(),
      bytes: resp.bodyBytes,
    );
  }

  /// The file itself, from the address asked for (not a sign-in page it
  /// was sent on to).
  static bool _isFile(http.Response resp, Uri url) {
    final landed = resp.request?.url;
    final type = resp.headers['content-type'] ?? '';
    return resp.statusCode == 200 &&
        landed != null &&
        landed.host == url.host &&
        landed.path == url.path &&
        !type.startsWith('text/html');
  }

  /// The course's checklists, each with its categories and items. A
  /// checklist whose categories or items students can't read is listed
  /// without them.
  Future<List<Checklist>> checklists(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final base = '$_le/$orgUnitId/checklists';
    final lists = [
      for (final row in await _all('$base/', onMfaChallenge))
        if (checklistFromJson(orgUnitId, row) case final c?) c,
    ];
    Future<List<Map<String, Object?>>> rows(String url) => _all(url, onMfaChallenge)
        .catchError((Object e) => e is LmsUnavailableException ? <Map<String, Object?>>[] : throw e);
    return Future.wait([
      for (final c in lists)
        Future.wait([rows('$base/${c.id}/categories/'), rows('$base/${c.id}/items/')])
            .then((r) => withCategories(c, r[0], r[1])),
    ]);
  }

  /// The surveys you can see in the course: open ones first.
  Future<List<Survey>> surveys(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final all = [
      for (final row in await _all('$_le/$orgUnitId/surveys/', onMfaChallenge))
        if (surveyFromJson(orgUnitId, row) case final s?) s,
    ];
    return sortSurveys(all, _now());
  }
}
