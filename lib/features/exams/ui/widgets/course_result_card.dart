import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/features/exams/domain/exam_results.dart';

/// One course on a result slip: its grade badge, title and facts.
class CourseResultCard extends StatelessWidget {
  final CourseResult course;

  /// Grade and grade points covered, and the badge left uncoloured so its
  /// colour doesn't give the grade away.
  final bool hidden;
  const CourseResultCard({super.key, required this.course, this.hidden = false});

  /// Colour by grade band: A greens, B blues, C/D ambers, F red, others grey.
  Tone _tone() {
    final g = course.grade.toUpperCase();
    if (g.startsWith('A') || g == 'PASS' || g == 'P') return Tone.success;
    if (g.startsWith('B')) return Tone.info;
    if (g.startsWith('C') || g.startsWith('D')) return Tone.warning;
    if (g.startsWith('F')) return Tone.danger;
    return Tone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = (hidden ? Tone.neutral : _tone()).colors(theme.colorScheme);
    final facts = [
      course.code,
      if (course.credits.isNotEmpty) '${course.credits} credits',
      if (!hidden && !course.inProgress && course.gradePoints.isNotEmpty) '${course.gradePoints} grade points',
      if (course.remark.isNotEmpty) course.remark,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Semantics(
              label: course.inProgress
                  ? 'In progress'
                  : hidden
                      ? 'Grade hidden'
                      : 'Grade ${course.grade}',
              excludeSemantics: true,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                // A longer grade (e.g. "Pass") shrinks to fit on one line.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    course.grade.isEmpty
                        ? '–'
                        : hidden && !course.inProgress
                            ? hiddenValue
                            : course.grade,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(facts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (course.inProgress) ...[
                    const SizedBox(height: 4),
                    const StatusPill(label: 'In progress', tone: Tone.neutral, icon: Icons.hourglass_bottom),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
