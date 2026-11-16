import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/due_tile.dart';

/// "Due soon" across this term's courses: each course's assignments and
/// quizzes are read side by side (a few requests at a time), and deadlines
/// show as they arrive. Hidden when nothing is due.
class TermDueSoon extends ConsumerWidget {
  final List<LmsCourse> courses;
  const TermDueSoon({super.key, required this.courses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final items = <DueItem>[];
    var loading = 0;
    for (final c in courses) {
      final due = ref.watch(lmsCourseDueProvider((id: c.orgUnitId, code: c.courseCode)));
      if (due.isLoading && !due.hasValue) loading++;
      items.addAll(due.valueOrNull ?? const []);
    }
    items.sort((a, b) => a.due.compareTo(b.due));
    if (items.isEmpty && loading == 0) return const SizedBox.shrink();
    final shown = items.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section - Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(loading > 0 ? 'Due soon · checking ${courses.length - loading} of ${courses.length}' : 'Due soon'),
          for (final d in shown) DueTile(item: d, now: now),
          if (items.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: Space.card),
              child: Text('+${items.length - shown.length} more in the courses below',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          if (shown.isEmpty) const Padding(padding: EdgeInsets.only(bottom: Space.card), child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
