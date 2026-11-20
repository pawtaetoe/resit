import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/discussions_providers.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/thread_card.dart';

/// What a topic's posts say in one line: "12 posts · 3 unread · last 4 Nov".
String topicSummary(TopicPosts p) => p.postCount == 0
    ? 'No posts yet'
    : [
        '${p.postCount} post${p.postCount == 1 ? '' : 's'}',
        if (p.unread case final n? when n > 0) '$n unread',
        if (p.lastPost != null) 'last ${DateFormat('d MMM').format(p.lastPost!)}',
      ].join(' · ');

/// A topic's threads, newest first, each with its replies indented under
/// it; [pageSize] threads at a time. Read only: the bottom bar opens the
/// topic on xSiTe for replying.
class TopicScreen extends StatefulWidget {
  final LmsCourse course;
  final DiscussionTopic topic;
  const TopicScreen({super.key, required this.course, required this.topic});

  static const pageSize = 20;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  var _shown = TopicScreen.pageSize;

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    return SectionScaffold<TopicPosts>(
      course: widget.course,
      title: topic.name.isEmpty ? 'Discussion' : topic.name,
      provider: lmsTopicPostsProvider(topic.key),
      xsitePage: topic.url,
      xsiteLabel: topic.canPost ? 'Reply on xSiTe' : 'Open in xSiTe',
      icon: Icons.forum_outlined,
      isEmpty: (p) => p.threads.isEmpty,
      emptyText: topic.mustPost ? "Post on xSiTe first to see others' posts" : 'No posts yet',
      builder: (context, posts) {
        final rest = posts.threads.length - _shown;
        return [
          _TopicHeader(topic: topic, posts: posts),
          for (final t in posts.threads.take(_shown)) ThreadCard(thread: t),
          if (rest > 0)
            Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _shown += TopicScreen.pageSize),
                icon: const Icon(Icons.expand_more),
                label: Text('Show more threads ($rest left)'),
              ),
            ),
        ];
      },
    );
  }
}

/// The topic's description, its counts, and whether it takes new posts.
class _TopicHeader extends StatelessWidget {
  final DiscussionTopic topic;
  final TopicPosts posts;
  const _TopicHeader({required this.topic, required this.posts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = topic.dueDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, Space.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topic.description.isNotEmpty) ...[MoreText(topic.description, lines: 3), const SizedBox(height: 8)],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${topicSummary(posts)} · ${posts.threads.length} thread${posts.threads.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (!topic.canPost)
                const StatusPill(label: 'Closed for new posts', tone: Tone.neutral, icon: Icons.lock_outline),
              if (due != null)
                StatusPill(
                    label: 'Post by ${DateFormat('d MMM, HH:mm').format(due)}', tone: Tone.info, icon: Icons.schedule),
              if (topic.mustPost)
                const StatusPill(
                    label: "Post first to see others' posts", tone: Tone.info, icon: Icons.visibility_outlined),
            ],
          ),
        ],
      ),
    );
  }
}
