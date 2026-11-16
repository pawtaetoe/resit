import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/features/exams/domain/exam_results.dart';
import 'package:resit/features/exams/ui/widgets/course_result_card.dart';

/// One term's result slip: its GPAs, standing, courses, note and the
/// slip's details. Grades stay hidden until the user shows them.
class ResultSlipView extends ConsumerWidget {
  final ExamResults results;
  const ResultSlipView({super.key, required this.results});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Grades and GPAs stay hidden until the user taps the eye.
    final visible = ref.watch(gradesVisibleProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    final graded = results.courses.where((c) => !c.inProgress).toList();
    final credits = graded.fold<double>(0, (sum, c) => sum + (double.tryParse(c.credits) ?? 0));
    final standing = results.value('Academic Standing');

    if (results.courses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          MessageView(
            icon: Icons.help_outline,
            title: "Couldn't read this result slip",
            message: 'in4SIT showed something the app doesn\'t recognise.',
            detail: results.pageText?.substring(0, results.pageText!.length.clamp(0, 400)),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
      children: [
        Text(results.heading, style: theme.textTheme.titleLarge),
        if (results.value('Programme') case final programme?)
          Text(programme, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _stat('Trimester GPA', results.value('Trimester GPA'), visible)),
              const SizedBox(width: Space.card),
              Expanded(child: _stat('Cumulative GPA', results.value('Cumulative GPA'), visible)),
            ],
          ),
        ),
        if (visible && standing != null && standing != '-') ...[
          const SizedBox(height: 8),
          StatusPill(label: 'Academic standing: $standing', tone: Tone.info),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Courses', style: theme.textTheme.titleMedium)),
            Text(
              '${results.courses.length} courses'
              '${credits > 0 ? ' · ${credits == credits.roundToDouble() ? credits.round() : credits} credits graded' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final c in results.courses)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: CourseResultCard(course: c, hidden: !visible)),
        if (results.note != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: muted),
              const SizedBox(width: 8),
              Expanded(child: Text(results.note!, style: theme.textTheme.bodySmall?.copyWith(color: muted))),
            ],
          ),
        ],
        if (results.details.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Slip details'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final (label, value) in results.details)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                        ),
                        Expanded(child: Text(value)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A GPA as a highlighted stat tile (value over label, as on Home and
/// Academic progress), hidden until the user shows grades.
Widget _stat(String label, String? value, bool visible) => StatTile(
      tinted: true,
      value: !visible
          ? hiddenValue
          : value == null || value.isEmpty
              ? '–'
              : value,
      caption: label,
      semanticsLabel: visible ? null : '$label, hidden',
    );
