import 'dart:convert';

import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';

// Reading xSiTe's discussion replies (forums, topics, posts) into the app's
// models, from Brightspace's documented "Valence" routes under
// /d2l/api/le/(version)/(orgUnitId)/discussions/.

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String _text(Object? v) => v is String ? v.trim() : '';

/// The list in a reply: a bare array, or an ObjectListPage's "Objects".
List<Map<String, Object?>> _list(String body) {
  final json = jsonDecode(stripGuard(body));
  final raw = json is List ? json : (json is Map ? json['Objects'] : null);
  return [
    for (final o in raw is List ? raw : const [])
      if (o is Map) o.cast<String, Object?>(),
  ];
}

typedef _Window = ({TopicAccess access, DateTime? at});

/// AVAILABILITY_T comes as a name or a number: AccessRestricted (0),
/// SubmissionRestricted (1), Hidden (2).
bool _isHiddenType(Object? t) => t == 2 || '$t' == '2' || '$t'.toLowerCase().contains('hidden');
bool _isSubmissionType(Object? t) => t == 1 || '$t' == '1' || '$t'.toLowerCase().contains('submission');

/// What a forum's or topic's dates (and their AVAILABILITY_T) mean for a
/// student [now]; null when they hide it.
_Window? _window(Map<String, Object?> j, DateTime now) {
  final start = _date(j['StartDate']), end = _date(j['EndDate']);
  if (start != null && start.isAfter(now)) {
    return _isHiddenType(j['StartDateAvailabilityType']) ? null : (access: TopicAccess.notYetOpen, at: start);
  }
  if (end != null && end.isBefore(now)) {
    final type = j['EndDateAvailabilityType'];
    if (_isHiddenType(type)) return null;
    // Without a type the posts usually stay readable; if xSiTe refuses them
    // after all, the topic shows as "not available".
    return (access: type == null || _isSubmissionType(type) ? TopicAccess.closed : TopicAccess.ended, at: end);
  }
  return (access: TopicAccess.open, at: null);
}

/// A course's forums (without their topics, read separately with
/// [parseTopics]), leaving out hidden ones and ones whose dates hide them.
List<DiscussionForum> parseForums(String body, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return [
    for (final j in _list(body))
      if ((_int(j['ForumId']), _window(j, at)) case (final id?, final w?) when j['IsHidden'] != true)
        DiscussionForum(
          id: id,
          name: _text(j['Name']),
          description: richText(j['Description']),
          access: w.access,
          accessDate: w.at,
          locked: j['IsLocked'] == true,
        ),
  ];
}

/// [forum]'s topics you can see, leaving out hidden ones and ones whose
/// dates hide them. A topic is as closed as the stricter of its own and its
/// forum's dates.
List<DiscussionTopic> parseTopics(String orgUnitId, DiscussionForum forum, String body, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final topics = <DiscussionTopic>[];
  for (final j in _list(body)) {
    final id = _int(j['TopicId']), own = _window(j, at);
    if (id == null || own == null || j['IsHidden'] == true) continue;
    // TopicAccess runs from most to least open.
    final w = forum.access.index > own.access.index ? (access: forum.access, at: forum.accessDate) : own;
    topics.add(DiscussionTopic(
      orgUnitId: orgUnitId,
      forumId: forum.id,
      id: id,
      name: _text(j['Name']),
      description: richText(j['Description']),
      access: w.access,
      accessDate: w.at,
      dueDate: _date(j['DueDate']),
      locked: j['IsLocked'] == true || forum.locked,
      mustPost: j['MustPostToParticipate'] == true,
    ));
  }
  return topics;
}

/// A page of a topic's posts, without deleted ones, and how many rows the
/// page had (deleted ones included), to tell a full page from the last.
({List<DiscussionPost> posts, int rows}) parsePosts(String body) {
  final rows = _list(body);
  return (posts: [for (final j in rows) if (_post(j) case final p?) p], rows: rows.length);
}

DiscussionPost? _post(Map<String, Object?> j) {
  final id = _int(j['PostId']);
  if (id == null || j['IsDeleted'] == true) return null;
  final read = j['IsRead'], files = j['Attachments'];
  return DiscussionPost(
    id: id,
    threadId: _int(j['ThreadId']) ?? id,
    parentId: _int(j['ParentPostId']),
    subject: _text(j['Subject']),
    author: j['IsAnonymous'] == true ? 'Anonymous' : _text(j['PostingUserDisplayName']),
    date: _date(j['DatePosted']),
    body: richText(j['Message']),
    isRead: read is bool ? read : null,
    attachments: _int(j['AttachmentCount']) ?? (files is List ? files.length : 0),
  );
}
