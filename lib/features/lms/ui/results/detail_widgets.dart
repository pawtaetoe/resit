import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

/// "Fri 21 Nov 2026, 23:59".
String fullDate(DateTime d) => DateFormat('EEE d MMM yyyy, HH:mm').format(d);

/// One labelled fact in a details card: icon, label, value.
class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const DetailRow({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: Space.dense),
          SizedBox(width: 96, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: muted))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A card of [DetailRow]s (or anything else) with the usual padding.
class DetailCard extends StatelessWidget {
  final List<Widget> children;
  const DetailCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.card),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.inset, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      );
}

/// A muted one-line note (e.g. "No feedback released yet").
class InfoNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const InfoNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted))),
        ],
      ),
    );
  }
}

/// An instructor's comment on a grade or on your work, as plain text.
/// Hidden with grades (a comment often gives the mark away).
class InstructorComment extends StatelessWidget {
  final String text;
  final String label;
  const InstructorComment(this.text, {super.key, this.label = "Instructor's comment"});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradeCurtain(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.comment_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          MoreText(text, lines: 3),
        ],
      ),
    );
  }
}

/// The grade-book entry that goes with an assignment or quiz: the grade
/// (hidden with grades), how much it counts, and the instructor's comment.
class MatchedGrade extends ConsumerWidget {
  final GradeEntry grade;
  const MatchedGrade({super.key, required this.grade});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visible = ref.watch(gradesVisibleProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    return DetailCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(grade.name.isEmpty ? 'Grade' : grade.name, style: theme.textTheme.titleSmall),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: visible ? null : 'Grade, hidden',
              excludeSemantics: !visible,
              child: Text(visible ? grade.summary : hiddenValue,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        if (visible && grade.weighted != null && grade.weightedOutOf != null && grade.weightedOutOf! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Counts ${grade.weighted!.toStringAsFixed(1)} of ${grade.weightedOutOf!.toStringAsFixed(1)} towards the course',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        if (grade.comment.isNotEmpty) ...[const SizedBox(height: 10), InstructorComment(grade.comment)],
      ],
    );
  }
}
