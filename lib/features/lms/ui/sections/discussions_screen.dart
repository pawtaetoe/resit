import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/lms/discussions_providers.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/topic_tile.dart';

/// A course's discussion forums, each with its topics. Read only: replying
/// happens on xSiTe.
class DiscussionsScreen extends StatelessWidget {
  final LmsCourse course;
  const DiscussionsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionScaffold<List<DiscussionForum>>(
      course: course,
      title: 'Discussions',
      provider: lmsDiscussionsProvider(course.orgUnitId),
      xsitePage: discussionsPage(course.orgUnitId),
      icon: Icons.forum_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: 'No discussions',
      builder: (context, forums) => [
        for (final (i, f) in forums.indexed) ...[
          if (i > 0) const SizedBox(height: Space.section - Space.card),
          SectionLabel(f.name),
          if (f.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(f.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          for (final t in f.topics) TopicTile(course: course, topic: t),
        ],
      ],
    );
  }
}
