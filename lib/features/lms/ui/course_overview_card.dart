import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/open_topic.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

/// The course overview (syllabus) from xSiTe's content tool, with its
/// attached file if any. Shows nothing while loading, when the course has
/// no overview, or when it can't be read: the content below matters more.
class CourseOverviewCard extends ConsumerStatefulWidget {
  final LmsCourse course;
  const CourseOverviewCard({super.key, required this.course});

  @override
  ConsumerState<CourseOverviewCard> createState() => _CourseOverviewCardState();
}

class _CourseOverviewCardState extends ConsumerState<CourseOverviewCard> {
  bool _opening = false;

  Future<void> _openAttachment() async {
    setState(() => _opening = true);
    try {
      await openOverviewAttachment(context, ref, widget.course);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(lmsOverviewProvider(widget.course.orgUnitId)).valueOrNull;
    if (overview == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Course overview', style: theme.textTheme.titleMedium)),
                ],
              ),
              if (overview.text.isNotEmpty) ...[const SizedBox(height: 8), MoreText(overview.text, lines: 4)],
              if (overview.hasAttachment) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _opening ? null : _openAttachment,
                  icon: _opening
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file),
                  label: const Text('Open attachment'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
