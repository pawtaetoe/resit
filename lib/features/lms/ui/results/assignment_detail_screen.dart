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
import 'package:resit/features/lms/ui/results/feedback_view.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';
import 'package:resit/sites/xsite/xsite_service.dart' show LmsUnavailableException;

/// One assignment: its dates and instructions, your submissions, and the
/// feedback and grade released to you.
class AssignmentDetailScreen extends ConsumerWidget {
  final LmsCourse course;
  final Assignment assignment;
  const AssignmentDetailScreen({super.key, required this.course, required this.assignment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ou = course.orgUnitId;
    final key = (orgUnitId: ou, id: assignment.id);
    // The latest copy from the course's list, once it's (re)loaded.
    final a = ref.watch(lmsAssignmentsProvider(ou)).valueOrNull?.where((x) => x.id == assignment.id).firstOrNull ??
        assignment;
    final feedback = ref.watch(assignmentFeedbackProvider(key));
    final grade = ref.watch(lmsGradesProvider(ou)).valueOrNull?.forItem(a.gradeItemId);
    final now = DateTime.now();

    Future<void> refresh() async {
      ref.invalidate(assignmentFeedbackProvider(key));
      ref.invalidate(lmsGradesProvider(ou));
      await ref.read(assignmentFeedbackProvider(key).future).then((_) {}).catchError((_) {});
    }

    final deadline = a.deadline;
    return AppScaffold(
      appBar: thumbAppBar(a.name, subtitle: '${course.courseCode} · Assignment'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => openInBrowser(context, a.url),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in xSiTe', overflow: TextOverflow.ellipsis),
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
                if (a.submitted)
                  const StatusPill(label: 'Submitted', tone: Tone.success, icon: Icons.check)
                else if (deadline != null)
                  StatusPill(
                    label: dueLabel(deadline, now),
                    tone: dueTone(deadline, now) == Tone.neutral ? Tone.info : dueTone(deadline, now),
                    icon: Icons.schedule,
                  ),
                if (a.isGroup) const StatusPill(label: 'Group', tone: Tone.neutral, icon: Icons.groups_outlined),
              ],
            ),
            const SizedBox(height: Space.card),
            if (a.startDate != null || a.dueDate != null || a.endDate != null || a.outOf != null)
              DetailCard(children: [
                if (a.startDate != null) DetailRow(icon: Icons.lock_open_outlined, label: 'Opens', value: fullDate(a.startDate!)),
                if (a.dueDate != null) DetailRow(icon: Icons.event_outlined, label: 'Due', value: fullDate(a.dueDate!)),
                if (a.endDate != null) DetailRow(icon: Icons.event_busy_outlined, label: 'Closes', value: fullDate(a.endDate!)),
                if (a.outOf != null) DetailRow(icon: Icons.grade_outlined, label: 'Out of', value: fmtNumber(a.outOf!)),
              ]),
            if (a.instructions.isNotEmpty) ...[
              const SizedBox(height: Space.card),
              const SectionLabel('Instructions'),
              DetailCard(children: [MoreText(a.instructions, lines: 8)]),
            ],
            const SizedBox(height: Space.card),
            const SectionLabel('Your submissions'),
            ..._submissions(a),
            const SizedBox(height: Space.card),
            const SectionLabel('Feedback'),
            switch (feedback) {
              AsyncValue(hasValue: true, value: null) => const InfoNote(icon: Icons.hourglass_empty, text: 'No feedback released yet.'),
              AsyncValue(hasValue: true, :final value?) => FeedbackView(
                  feedback: value,
                  outOf: a.outOf ?? grade?.outOf,
                  onOpenAttachments: () => openInBrowser(context, feedbackPage(a, value.entity)),
                ),
              AsyncError(:final error) when error is LmsUnavailableException =>
                const InfoNote(icon: Icons.info_outline, text: "xSiTe doesn't show feedback for this assignment here."),
              AsyncError(:final error) => InfoNote(icon: Icons.cloud_off, text: friendlyError(error)),
              _ => const InfoNote(icon: Icons.hourglass_empty, text: 'Checking for feedback…'),
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

  static List<Widget> _submissions(Assignment a) {
    final s = a.submissions;
    if (s == null) return const [InfoNote(icon: Icons.help_outline, text: "xSiTe didn't say whether you've submitted.")];
    if (s.isEmpty) return const [InfoNote(icon: Icons.upload_file_outlined, text: 'Not submitted yet.')];
    return [
      DetailCard(children: [
        for (final (i, d) in s.indexed)
          DetailRow(
            icon: i == 0 ? Icons.check_circle_outline : Icons.history,
            label: i == 0 ? 'Latest' : 'Earlier',
            value: fullDate(d),
          ),
      ]),
    ];
  }
}
