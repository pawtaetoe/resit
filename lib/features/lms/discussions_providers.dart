import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/lms_providers.dart';

// A course's discussions, by xSiTe course id. Kept once loaded until
// refreshed or signed out, like the other course sections.

/// The course's forums and the topics in them you can see.
final lmsDiscussionsProvider = FutureProvider.family<List<DiscussionForum>, String>(
    (ref, id) => ref.watch(lmsServiceProvider).discussions.forums(id));

/// One topic's posts, in threads. Refreshing the course's discussions
/// refreshes its topics' posts too.
final lmsTopicPostsProvider = FutureProvider.family<TopicPosts, TopicKey>((ref, topic) {
  ref.watch(lmsDiscussionsProvider(topic.orgUnitId).future).ignore();
  return ref.watch(lmsServiceProvider).discussions.posts(topic);
});
