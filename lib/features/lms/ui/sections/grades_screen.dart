import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/results/detail_widgets.dart';

class GradesScreen extends ConsumerWidget {
  final LmsCourse course;
  const GradesScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visible = ref.watch(gradesVisibleProvider);
    String v(String s) => visible ? s : hiddenValue;
    return SectionScaffold<CourseGrades>(
      course: course,
      title: 'Grades',
      provider: lmsGradesProvider(course.orgUnitId),
      xsitePage: courseToolPage('/d2l/lms/grades/index.d2l', course.orgUnitId),
      icon: Icons.grade_outlined,
      isEmpty: (g) => g.items.isEmpty && g.finalGrade == null,
      emptyText: 'No grades released yet',
      barExtra: const GradeVisibilityButton(inBar: true),
      builder: (context, g) => [
        if (g.finalGrade case final f?) ...[
          StatTile(
            tinted: true,
            value: v(f.summary),
            caption: 'final grade',
            semanticsLabel: visible ? null : 'Final grade, hidden',
          ),
          if (f.comment.isNotEmpty) ...[
            const SizedBox(height: Space.card),
            DetailCard(children: [InstructorComment(f.comment)]),
          ],
          const SizedBox(height: Space.section),
        ],
        for (final e in g.items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.card),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name, style: theme.textTheme.titleSmall),
                              if (e.type.isNotEmpty)
                                Text(e.type,
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: visible ? null : '${e.name}, hidden',
                          excludeSemantics: !visible,
                          child: Text(v(e.summary),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    if (visible && e.weighted != null && e.weightedOutOf != null && e.weightedOutOf! > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Counts ${e.weighted!.toStringAsFixed(1)} of ${e.weightedOutOf!.toStringAsFixed(1)} towards the course',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    if (e.comment.isNotEmpty) ...[const SizedBox(height: 10), InstructorComment(e.comment)],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
