import 'package:resit/features/lms/domain/courses.dart';

/// Which topic of which course: the key a topic's posts are kept under.
typedef TopicKey = ({String orgUnitId, int forumId, int topicId});

/// A discussion forum and the topics in it you can see.
class DiscussionForum {
  final int id;
  final String name;
  final String description;

  /// The forum's own dates and lock, which its topics inherit.
  final TopicAccess access;
  final DateTime? accessDate;
  final bool locked;
  final List<DiscussionTopic> topics;

  const DiscussionForum({
    required this.id,
    required this.name,
    this.description = '',
    this.access = TopicAccess.open,
    this.accessDate,
    this.locked = false,
    this.topics = const [],
  });

  DiscussionForum withTopics(List<DiscussionTopic> t) => DiscussionForum(
      id: id,
      name: name,
      description: description,
      access: access,
      accessDate: accessDate,
      locked: locked,
      topics: t);
}

/// Whether a topic's posts can be read now, from most to least open.
enum TopicAccess {
  /// Open for reading (and, unless [DiscussionTopic.locked], posting).
  open,

  /// Past its end date but still readable; no new posts.
  closed,

  /// Not open yet: shown with its opening date, nothing to read.
  notYetOpen,

  /// Past its end date and no longer readable.
  ended,
}

class DiscussionTopic {
  final String orgUnitId;
  final int forumId;
  final int id;
  final String name;
  final String description;
  final TopicAccess access;

  /// When it opens ([TopicAccess.notYetOpen]) or closed ([closed]/[ended]).
  final DateTime? accessDate;
  final DateTime? dueDate;

  /// No new posts (xSiTe's lock).
  final bool locked;

  /// Others' posts show only once you've posted in it.
  final bool mustPost;

  const DiscussionTopic({
    required this.orgUnitId,
    required this.forumId,
    required this.id,
    required this.name,
    this.description = '',
    this.access = TopicAccess.open,
    this.accessDate,
    this.dueDate,
    this.locked = false,
    this.mustPost = false,
  });

  TopicKey get key => (orgUnitId: orgUnitId, forumId: forumId, topicId: id);

  /// Its posts can be read now.
  bool get readable => access == TopicAccess.open || access == TopicAccess.closed;

  /// New posts are accepted (on xSiTe).
  bool get canPost => access == TopicAccess.open && !locked;

  /// The topic's page on xSiTe, where replying happens.
  Uri get url => Uri.parse('$xsiteBase/d2l/le/$orgUnitId/discussions/topics/$id/View');
}

/// The discussions list of a course on xSiTe.
Uri discussionsPage(String orgUnitId) => Uri.parse('$xsiteBase/d2l/le/$orgUnitId/discussions/List');

class DiscussionPost {
  final int id;
  final int threadId;
  final int? parentId;
  final String subject;
  final String author;
  final DateTime? date;
  final String body;

  /// Null when xSiTe didn't say.
  final bool? isRead;
  final int attachments;

  const DiscussionPost({
    required this.id,
    required this.threadId,
    this.parentId,
    this.subject = '',
    this.author = '',
    this.date,
    this.body = '',
    this.isRead,
    this.attachments = 0,
  });

  bool get isUnread => isRead == false;
}

/// A reply and how deep it sits under the thread's first post (1 = a
/// direct reply).
typedef Reply = ({int depth, DiscussionPost post});

class DiscussionThread {
  final DiscussionPost first;

  /// In reading order: each reply right after the post it answers, oldest
  /// first among siblings.
  final List<Reply> replies;

  const DiscussionThread(this.first, [this.replies = const []]);

  /// When anything was last posted in the thread.
  DateTime? get lastPost => [first, for (final r in replies) r.post]
      .map((p) => p.date)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
}

/// A topic's posts, in threads, newest thread first.
class TopicPosts {
  final List<DiscussionThread> threads;
  final int postCount;

  /// Null when xSiTe doesn't say which posts you've read.
  final int? unread;
  final DateTime? lastPost;

  const TopicPosts({this.threads = const [], this.postCount = 0, this.unread, this.lastPost});

  /// Groups [posts] into threads: each thread's first post with its replies
  /// nested under it. A reply whose post it answers isn't there (deleted)
  /// goes straight under the first post; a thread whose first post isn't
  /// there starts at its oldest remaining post.
  factory TopicPosts.from(List<DiscussionPost> posts) {
    DateTime dateOf(DiscussionPost p) => p.date ?? DateTime(0);
    int oldestFirst(DiscussionPost a, DiscussionPost b) {
      final c = dateOf(a).compareTo(dateOf(b));
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    final byThread = <int, List<DiscussionPost>>{};
    for (final p in posts) {
      byThread.putIfAbsent(p.threadId, () => []).add(p);
    }
    final threads = <DiscussionThread>[];
    for (final MapEntry(key: threadId, value: list) in byThread.entries) {
      list.sort(oldestFirst);
      final first = list.firstWhere((p) => p.id == threadId || p.parentId == null, orElse: () => list.first);
      final ids = {for (final p in list) p.id};
      final children = <int, List<DiscussionPost>>{};
      for (final p in list) {
        if (identical(p, first)) continue;
        final parent = p.parentId != null && ids.contains(p.parentId) && p.parentId != p.id ? p.parentId! : first.id;
        children.putIfAbsent(parent, () => []).add(p);
      }
      final replies = <Reply>[];
      final seen = <int>{first.id};
      void walk(int id, int depth) {
        for (final c in children[id] ?? const <DiscussionPost>[]) {
          if (!seen.add(c.id)) continue;
          replies.add((depth: depth, post: c));
          walk(c.id, depth + 1);
        }
      }

      walk(first.id, 1);
      // Posts in a loop of replies (a malformed reply) still show.
      for (final p in list) {
        if (seen.add(p.id)) replies.add((depth: 1, post: p));
      }
      threads.add(DiscussionThread(first, replies));
    }
    threads.sort((a, b) => oldestFirst(b.first, a.first));
    final dates = posts.map((p) => p.date).whereType<DateTime>();
    return TopicPosts(
      threads: threads,
      postCount: posts.length,
      unread: posts.any((p) => p.isRead != null) ? posts.where((p) => p.isUnread).length : null,
      lastPost: dates.isEmpty ? null : dates.reduce((a, b) => b.isAfter(a) ? b : a),
    );
  }
}
