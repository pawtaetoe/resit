import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/sections/checklist_card.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/survey_card.dart';

/// A course's checklists (categories and items, with due dates) and the
/// surveys you can take. Read only: checklists are ticked and surveys taken
/// on xSiTe.
class ChecklistsSurveysScreen extends ConsumerWidget {
  final LmsCourse course;
  const ChecklistsSurveysScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lmsChecklistsSurveysProvider(course.orgUnitId);
    final loaded = ref.watch(provider).valueOrNull;
    final now = DateTime.now();
    // The bar opens the tool the course uses: surveys if it has only those.
    final surveysOnly = (loaded?.checklists?.isEmpty ?? true) && (loaded?.surveys?.isNotEmpty ?? false);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SectionScaffold<ChecklistsAndSurveys>(
      course: course,
      title: 'Checklists and surveys',
      provider: provider,
      xsitePage: surveysOnly
          ? courseToolPage('/d2l/lms/survey/user/surveys_list.d2l', course.orgUnitId)
          : courseToolPage('/d2l/lms/checklist/checklists.d2l', course.orgUnitId),
      icon: Icons.checklist,
      isEmpty: (v) => v.isEmpty,
      emptyText: 'No checklists or surveys',
      builder: (context, v) => [
        if (v.checklists case final lists? when lists.isNotEmpty) ...[
          const SectionLabel('Checklists'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text("xSiTe doesn't share which items you've ticked; open a checklist there to tick them.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
          ),
          for (final c in lists) ChecklistCard(checklist: c, now: now),
          const SizedBox(height: 16),
        ],
        if (v.surveys case final surveys? when surveys.isNotEmpty) ...[
          const SectionLabel('Surveys'),
          for (final s in surveys) SurveyCard(survey: s, now: now),
        ],
      ],
    );
  }
}
