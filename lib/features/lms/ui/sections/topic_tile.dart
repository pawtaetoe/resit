import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/discussions_providers.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/ui/sections/topic_screen.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

String _day(DateTime d) => DateFormat('d MMM').format(d);

/// One topic in the discussions list: its posts' count, unread count and
/// last post date once read, or when it opens or closed. Opens the topic.
class TopicTile extends ConsumerWidget {
  final LmsCourse course;
  final DiscussionTopic topic;
  const TopicTile({super.key, required this.course, required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final posts = topic.readable ? ref.watch(lmsTopicPostsProvider(topic.key)) : null;
    final unread = posts?.valueOrNull?.unread ?? 0;
    final at = topic.accessDate;
    final status = switch (topic.access) {
      TopicAccess.notYetOpen => at == null ? 'Not open yet' : 'Opens ${_day(at)}, ${DateFormat('HH:mm').format(at)}',
      TopicAccess.ended => at == null ? 'Closed' : 'Closed ${_day(at)}',
      TopicAccess.closed => at == null ? 'Closed for new posts' : 'Closed for new posts ${_day(at)}',
      TopicAccess.open => topic.locked ? 'Locked' : null,
    };
    final counts = posts?.when(
      data: topicSummary,
      loading: () => 'Loading…',
      error: (e, _) => e is LmsUnavailableException ? 'Not available' : "Couldn't load",
    );
    final subtitle = [if (counts != null) counts, if (status != null) status].join('\n');

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: topic.readable,
          onTap: topic.readable
              ? () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => TopicScreen(course: course, topic: topic)))
              : null,
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Icon(switch (topic.access) {
              TopicAccess.notYetOpen => Icons.schedule,
              TopicAccess.open when !topic.locked => Icons.forum_outlined,
              _ => Icons.lock_outline,
            }),
          ),
          title: Text(topic.name,
              style: unread > 0
                  ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
                  : theme.textTheme.titleMedium),
          subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: topic.readable ? const Icon(Icons.chevron_right) : null,
        ),
      ),
    );
  }
}
