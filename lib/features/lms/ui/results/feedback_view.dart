import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/features/lms/domain/results.dart';
import 'package:resit/features/lms/ui/results/detail_widgets.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

/// Released feedback on an assignment: the score (hidden with grades), the
/// instructor's comments, rubric results and attached files (opened on
/// xSiTe with [onOpenAttachments]).
class FeedbackView extends ConsumerWidget {
  final AssignmentFeedback feedback;

  /// What the folder is marked out of, when known.
  final double? outOf;
  final VoidCallback onOpenAttachments;

  const FeedbackView({super.key, required this.feedback, required this.outOf, required this.onOpenAttachments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(gradesVisibleProvider);
    final f = feedback;
    final hasScore = f.score != null || (f.symbol ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasScore)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.card),
            child: StatTile(
              tinted: true,
              icon: Icons.grade_outlined,
              value: visible ? f.scoreLabel(outOf) : hiddenValue,
              caption: 'score on this assignment',
              semanticsLabel: visible ? null : 'Score, hidden',
            ),
          ),
        if (f.comments.isNotEmpty) DetailCard(children: [InstructorComment(f.comments, label: "Instructor's comments")]),
        for (final r in f.rubrics) RubricCard(rubric: r),
        if (f.attachments.isNotEmpty) _Attachments(names: f.attachments, onOpen: onOpenAttachments),
      ],
    );
  }
}

/// A rubric's results: overall level and each criterion's level, score and
/// feedback. Hidden with grades.
class RubricCard extends StatelessWidget {
  final RubricResult rubric;
  const RubricCard({super.key, required this.rubric});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final r = rubric;
    String? points(double? score, double? outOf) {
      if (!r.showScores || score == null) return null;
      return outOf != null && outOf > 0 ? '${fmtNumber(score)} / ${fmtNumber(outOf)}' : fmtNumber(score);
    }

    final overall = [
      if (r.overallLevel case final level? when level.isNotEmpty) level,
      if (points(r.score, null) case final p?) p,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: GradeCurtain(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.inset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.table_chart_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r.name, style: theme.textTheme.titleSmall)),
                  ],
                ),
                if (overall.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Overall: $overall', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                if (r.feedback.isNotEmpty) ...[const SizedBox(height: 4), MoreText(r.feedback, lines: 3)],
                for (final c in r.criteria) ...[
                  const Divider(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.criterion, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            if (c.level != null && c.level!.isNotEmpty)
                              Text(c.level!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                          ],
                        ),
                      ),
                      if (points(c.score, c.outOf) case final p?) ...[
                        const SizedBox(width: 12),
                        Text(p, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                  if (c.feedback.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4), child: MoreText(c.feedback, lines: 2)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Names of the files and links attached to feedback; tapping opens the
/// feedback page on xSiTe, where they can be downloaded.
class _Attachments extends StatelessWidget {
  final List<String> names;
  final VoidCallback onOpen;
  const _Attachments({required this.names, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final n in names)
              ListTile(
                leading: Icon(Icons.attach_file, color: muted),
                title: Text(n, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Feedback attachment · opens on xSiTe'),
                trailing: Icon(Icons.open_in_new, size: 18, color: muted),
                onTap: onOpen,
              ),
          ],
        ),
      ),
    );
  }
}
