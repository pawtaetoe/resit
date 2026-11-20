import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/results/assignment_detail_screen.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

class AssignmentsScreen extends ConsumerWidget {
  final LmsCourse course;
  const AssignmentsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final grades = ref.watch(lmsGradesProvider(course.orgUnitId)).valueOrNull;
    final visible = ref.watch(gradesVisibleProvider);
    return SectionScaffold<List<Assignment>>(
      course: course,
      title: 'Assignments',
      provider: lmsAssignmentsProvider(course.orgUnitId),
      xsitePage: courseToolPage('/d2l/lms/dropbox/dropbox.d2l', course.orgUnitId),
      icon: Icons.assignment_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: 'No assignments',
      barExtra: const GradeVisibilityButton(inBar: true),
      builder: (context, list) => [
        for (final a in list)
          Builder(builder: (context) {
            final score = grades?.forItem(a.gradeItemId);
            final deadline = a.deadline;
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.card),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => AssignmentDetailScreen(course: course, assignment: a))),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(a.name, style: theme.textTheme.titleMedium)),
                            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (a.submitted)
                              StatusPill(
                                label: 'Submitted ${DateFormat('d MMM, HH:mm').format(a.lastSubmitted!)}',
                                tone: Tone.success,
                                icon: Icons.check,
                              )
                            else if (deadline != null)
                              StatusPill(
                                label: dueLabel(deadline, now),
                                tone: dueTone(deadline, now) == Tone.neutral ? Tone.info : dueTone(deadline, now),
                                icon: Icons.schedule,
                              ),
                            if (a.submitted && deadline != null)
                              StatusPill(label: dueLabel(deadline, now), tone: Tone.neutral, icon: Icons.schedule),
                            if (a.isGroup) const StatusPill(label: 'Group', tone: Tone.neutral, icon: Icons.groups_outlined),
                            if (score != null)
                              StatusPill(
                                label: 'Grade: ${visible ? score.summary : hiddenValue}',
                                tone: Tone.info,
                                icon: Icons.grade_outlined,
                              ),
                          ],
                        ),
                        if (a.instructions.isNotEmpty) ...[const SizedBox(height: 8), MoreText(a.instructions, lines: 3)],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
