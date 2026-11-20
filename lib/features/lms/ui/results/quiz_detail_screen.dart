import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/results_providers.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/features/lms/ui/results/detail_widgets.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';
import 'package:resit/sites/xsite/xsite_service.dart' show LmsUnavailableException;

/// One quiz: when it's open, its limits, your attempts (with scores once
/// released) and its grade; taking it happens on xSiTe.
class QuizDetailScreen extends ConsumerWidget {
  final LmsCourse course;
  final Quiz quiz;
  const QuizDetailScreen({super.key, required this.course, required this.quiz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ou = course.orgUnitId;
    final key = (orgUnitId: ou, id: quiz.id);
    final q = ref.watch(lmsQuizzesProvider(ou)).valueOrNull?.where((x) => x.id == quiz.id).firstOrNull ?? quiz;
    final attempts = ref.watch(quizAttemptsProvider(key));
    final grade = ref.watch(lmsGradesProvider(ou)).valueOrNull?.forItem(q.gradeItemId);
    final now = DateTime.now();

    Future<void> refresh() async {
      ref.invalidate(quizAttemptsProvider(key));
      ref.invalidate(lmsGradesProvider(ou));
      await ref.read(quizAttemptsProvider(key).future).then((_) {}).catchError((_) {});
    }

    final deadline = q.deadline;
    final opens = q.startDate != null && q.startDate!.isAfter(now) ? q.startDate : null;
    final closed = q.endDate != null && q.endDate!.isBefore(now);
    return AppScaffold(
      appBar: thumbAppBar(q.name, subtitle: '${course.courseCode} · Quiz'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openInBrowser(context, q.url),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open quiz on xSiTe', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            const GradeVisibilityButton(inBar: true),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (opens != null)
                  const StatusPill(label: 'Not open yet', tone: Tone.neutral, icon: Icons.lock_clock_outlined)
                else if (closed)
                  const StatusPill(label: 'Closed', tone: Tone.neutral)
                else if (deadline != null)
                  StatusPill(
                    label: dueLabel(deadline, now),
                    tone: dueTone(deadline, now) == Tone.neutral ? Tone.info : dueTone(deadline, now),
                    icon: Icons.schedule,
                  )
                else
                  const StatusPill(label: 'Open', tone: Tone.info),
              ],
            ),
            const SizedBox(height: Space.card),
            DetailCard(children: [
              if (q.startDate != null) DetailRow(icon: Icons.lock_open_outlined, label: 'Opens', value: fullDate(q.startDate!)),
              if (q.dueDate != null) DetailRow(icon: Icons.event_outlined, label: 'Due', value: fullDate(q.dueDate!)),
              if (q.endDate != null) DetailRow(icon: Icons.event_busy_outlined, label: 'Closes', value: fullDate(q.endDate!)),
              DetailRow(
                icon: Icons.timer_outlined,
                label: 'Time limit',
                value: q.timeLimit == null ? 'None' : '${q.timeLimit} min',
              ),
              DetailRow(
                icon: Icons.replay_outlined,
                label: 'Attempts',
                value: q.attemptsAllowed == null ? 'Unlimited' : '${q.attemptsAllowed} allowed',
              ),
            ]),
            if (q.description.isNotEmpty) ...[
              const SizedBox(height: Space.card),
              const SectionLabel('About this quiz'),
              DetailCard(children: [MoreText(q.description, lines: 8)]),
            ],
            const SizedBox(height: Space.card),
            const SectionLabel('Your attempts'),
            ...switch (attempts) {
              AsyncValue(hasValue: true, :final value?) when value.isEmpty => [
                  const InfoNote(icon: Icons.hourglass_empty, text: 'No attempts yet.'),
                ],
              AsyncValue(hasValue: true, :final value?) => [for (final a in value) AttemptCard(attempt: a)],
              AsyncError(:final error) when error is LmsUnavailableException => [
                  const InfoNote(icon: Icons.info_outline, text: "xSiTe doesn't show your attempts here. Open the quiz on xSiTe."),
                ],
              AsyncError(:final error) => [InfoNote(icon: Icons.cloud_off, text: friendlyError(error))],
              _ => [const InfoNote(icon: Icons.hourglass_empty, text: 'Checking your attempts…')],
            },
            if (grade != null) ...[
              const SizedBox(height: Space.card),
              const SectionLabel('Grade'),
              MatchedGrade(grade: grade),
            ],
          ],
        ),
      ),
    );
  }
}

/// One attempt: when, and its score once released (hidden with grades).
class AttemptCard extends ConsumerWidget {
  final QuizAttempt attempt;
  const AttemptCard({super.key, required this.attempt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visible = ref.watch(gradesVisibleProvider);
    final a = attempt;
    final when = a.completed != null
        ? 'Completed ${fullDate(a.completed!)}'
        : (a.started != null ? 'Started ${fullDate(a.started!)} · in progress' : 'In progress');
    final score = a.released ? a.score : null;
    return DetailCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attempt ${a.number}', style: theme.textTheme.titleSmall),
                  Text(when, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (score != null)
              Semantics(
                label: visible ? null : 'Score, hidden',
                excludeSemantics: !visible,
                child: Text(visible ? fmtNumber(score) : hiddenValue,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              )
            else if (!a.inProgress)
              const StatusPill(label: 'Results not released', tone: Tone.neutral),
          ],
        ),
        if (a.released && a.feedback.isNotEmpty) ...[
          const SizedBox(height: 8),
          InstructorComment(a.feedback, label: 'Feedback'),
        ],
      ],
    );
  }
}
