import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/results/quiz_detail_screen.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

class QuizzesScreen extends ConsumerWidget {
  final LmsCourse course;
  const QuizzesScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final grades = ref.watch(lmsGradesProvider(course.orgUnitId)).valueOrNull;
    final visible = ref.watch(gradesVisibleProvider);
    return SectionScaffold<List<Quiz>>(
      course: course,
      title: 'Quizzes',
      provider: lmsQuizzesProvider(course.orgUnitId),
      xsitePage: courseToolPage('/d2l/lms/quizzing/quizzing.d2l', course.orgUnitId),
      icon: Icons.quiz_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: 'No quizzes',
      barExtra: const GradeVisibilityButton(inBar: true),
      builder: (context, list) => [
        for (final q in list)
          Builder(builder: (context) {
            final score = grades?.forItem(q.gradeItemId);
            final deadline = q.deadline;
            final opens = q.startDate != null && q.startDate!.isAfter(now) ? q.startDate : null;
            final closed = q.endDate != null && q.endDate!.isBefore(now);
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.card),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => QuizDetailScreen(course: course, quiz: q))),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(q.name, style: theme.textTheme.titleMedium)),
                            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (score != null)
                              StatusPill(
                                label: 'Score: ${visible ? score.summary : hiddenValue}',
                                tone: Tone.success,
                                icon: Icons.grade_outlined,
                              ),
                            if (opens != null)
                              StatusPill(label: 'Opens ${DateFormat('EEE d MMM, HH:mm').format(opens)}', tone: Tone.neutral)
                            else if (closed)
                              const StatusPill(label: 'Closed', tone: Tone.neutral)
                            else if (deadline != null)
                              StatusPill(
                                label: dueLabel(deadline, now),
                                tone: dueTone(deadline, now) == Tone.neutral ? Tone.info : dueTone(deadline, now),
                                icon: Icons.schedule,
                              ),
                            StatusPill(
                              label: q.attemptsAllowed == null
                                  ? 'Unlimited attempts'
                                  : '${q.attemptsAllowed} attempt${q.attemptsAllowed == 1 ? '' : 's'}',
                              tone: Tone.neutral,
                            ),
                            if (q.timeLimit != null)
                              StatusPill(label: '${q.timeLimit} min', tone: Tone.neutral, icon: Icons.timer_outlined),
                          ],
                        ),
                        if (q.description.isNotEmpty) ...[const SizedBox(height: 8), MoreText(q.description, lines: 3)],
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
