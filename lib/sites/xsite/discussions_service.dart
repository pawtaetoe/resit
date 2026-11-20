import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/discussion_parsers.dart';
import 'package:resit/sites/xsite/lms_unavailable_exception.dart';
import 'package:resit/sites/xsite/xsite_client.dart';

/// Reads a course's discussions on xSiTe: forums, their topics, and a
/// topic's posts. Read only: nothing is posted, rated or marked read.
class XsiteDiscussions {
  final XsiteClient _xsite;
  XsiteDiscussions(this._xsite);

  static const _le = '$xsiteBase/d2l/api/le/1.75';

  /// Posts asked for per page, and pages read at most.
  static const pageSize = 200;
  static const maxPages = 10;

  Future<String> _get(Uri url, void Function(MfaChallenge)? onMfaChallenge) =>
      _xsite.getJson(url, onMfaChallenge, limited: true);

  /// A course's forums you can see, each with the topics in it you can see.
  /// Forums with no such topics are left out.
  Future<List<DiscussionForum>> forums(String orgUnitId, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final base = '$_le/$orgUnitId/discussions/forums';
    final forums = parseForums(await _get(Uri.parse('$base/'), onMfaChallenge));
    final withTopics = await Future.wait([
      for (final f in forums)
        _get(Uri.parse('$base/${f.id}/topics/'), onMfaChallenge)
            .then((b) => f.withTopics(parseTopics(orgUnitId, f, b)))
            // xSiTe answers 404 for a forum with no topics.
            .catchError((Object _) => f, test: (e) => e is LmsUnavailableException),
    ]);
    return [for (final f in withTopics) if (f.topics.isNotEmpty) f];
  }

  /// A topic's posts, in threads, newest thread first. Pages through them
  /// ([pageSize] at a time, [maxPages] at most).
  Future<TopicPosts> posts(TopicKey topic, {void Function(MfaChallenge)? onMfaChallenge}) async {
    final url = Uri.parse('$_le/${topic.orgUnitId}/discussions/forums/${topic.forumId}/topics/${topic.topicId}/posts/');
    final all = <int, DiscussionPost>{};
    for (var page = 1; page <= maxPages; page++) {
      final body = await _get(url.replace(queryParameters: {'pageSize': '$pageSize', 'pageNumber': '$page'}), onMfaChallenge);
      final (:posts, :rows) = parsePosts(body);
      final before = all.length;
      for (final p in posts) {
        all[p.id] = p;
      }
      // A short page is the last; stop too if a page brings nothing new
      // (paging ignored).
      if (rows < pageSize || (posts.isNotEmpty && all.length == before)) break;
    }
    return TopicPosts.from(all.values.toList());
  }
}
