import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/exams/exams_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/exams/ui/exam_results_screen.dart';
import 'package:resit/features/exams/ui/widgets/academic_progress_cards.dart';
import 'package:resit/core/widgets/desktop.dart';

/// Charts of the academic record: GPA by term, credits per term, and the
/// spread of grades, each with a table view.
class AcademicProgressScreen extends ConsumerStatefulWidget {
  const AcademicProgressScreen({super.key});

  @override
  ConsumerState<AcademicProgressScreen> createState() => _AcademicProgressScreenState();
}

class _AcademicProgressScreenState extends ConsumerState<AcademicProgressScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(academicRecordServiceProvider).load(force: true);
      ref.invalidate(savedAcademicRecordProvider);
      ref.invalidate(academicRecordProvider);
      await ref.read(academicRecordProvider.future);
    } catch (e) {
      if (mounted) showError(context, "Couldn't update: ${friendlyError(e)}");
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(academicRecordProvider);
    final record = async.valueOrNull ?? ref.watch(savedAcademicRecordProvider).valueOrNull;

    return AppScaffold(
      appBar: thumbAppBar('Academic progress'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const ExamResultsScreen(fromProgress: true))),
                icon: const Icon(Icons.grading_outlined),
                label: const Text('Exam results', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            const GradeVisibilityButton(inBar: true),
          ],
        ),
      ),
      body: record == null
          ? (async.hasError
              ? MessageView(
                  icon: Icons.cloud_off,
                  tone: Tone.danger,
                  title: "Couldn't load your results",
                  message: friendlyError(async.error!),
                  action: FilledButton.icon(
                      onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                )
              : async.isLoading
                  ? ValueListenableBuilder<(int, int)?>(
                      valueListenable: ref.watch(academicRecordServiceProvider).progress,
                      builder: (context, p, _) => MessageView(
                        icon: Icons.insights_outlined,
                        title: 'Adding up your results…',
                        message: p == null
                            ? 'Reading each term from in4SIT. This can take a little while the first time.'
                            : 'Reading term ${p.$1 + 1} of ${p.$2} from in4SIT.',
                        action: SizedBox(
                          width: 160,
                          child: LinearProgressIndicator(value: p == null || p.$2 == 0 ? null : p.$1 / p.$2),
                        ),
                      ),
                    )
                  : MessageView(
                      icon: Icons.insights_outlined,
                      title: 'No results yet',
                      message: 'Sign in to see your progress.',
                      action: ref.watch(authStateProvider)
                          ? null
                          : FilledButton.icon(
                              onPressed: () => goToAccount(context, ref),
                              icon: const Icon(Icons.login),
                              label: const Text('Go to sign in'),
                            ),
                    ))
          : Column(children: [
              RefreshStrip(active: _refreshing),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
                    children: [
                      AcademicTotals(record: record),
                      const SizedBox(height: Space.page),
                      if (record.terms.isEmpty)
                        const MessageView(
                          compact: true,
                          icon: Icons.insights_outlined,
                          title: 'Charts are on their way',
                          message: 'Pull down to read each term from in4SIT.',
                        )
                      else ...[
                        GpaChartCard(terms: record.terms),
                        const SizedBox(height: 12),
                        CreditsChartCard(terms: record.terms),
                        if (record.gradeCounts.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          GradesChartCard(counts: record.gradeCounts),
                        ],
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'From your in4SIT result slips, updated ${DateFormat('d MMM, HH:mm').format(record.fetchedAt)}. '
                        'Pull down to update.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
    );
  }
}
