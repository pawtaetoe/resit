import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/charts.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/exams/data/academic_record.dart';
import 'package:resit/features/exams/presentation/exam_results_screen.dart';

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

    return Scaffold(
      appBar: thumbAppBar('Academic progress'),
      bottomNavigationBar: ThumbBar(
        child: FilledButton.tonalIcon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExamResultsScreen())),
          icon: const Icon(Icons.grading_outlined),
          label: const Text('Result slips'),
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
                  ? const MessageView(
                      icon: Icons.insights_outlined,
                      title: 'Adding up your results…',
                      message: 'Reading each term from in4SIT. This can take a little while the first time.',
                      action: SizedBox(width: 160, child: LinearProgressIndicator()),
                    )
                  : const MessageView(
                      icon: Icons.insights_outlined,
                      title: 'No results yet',
                      message: 'Sign in to see your progress.',
                    ))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_refreshing) const LinearProgressIndicator(),
                  _Totals(record: record),
                  const SizedBox(height: 16),
                  if (record.terms.isEmpty)
                    const MessageView(
                      icon: Icons.insights_outlined,
                      title: 'Charts are on their way',
                      message: 'Pull down to read each term from in4SIT.',
                    )
                  else ...[
                    _GpaCard(terms: record.terms),
                    const SizedBox(height: 12),
                    _CreditsCard(terms: record.terms),
                    if (record.gradeCounts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _GradesCard(counts: record.gradeCounts),
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
    );
  }
}

String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

class _Totals extends StatelessWidget {
  final AcademicRecord record;
  const _Totals({required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label) => Expanded(
          child: Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                  Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                ],
              ),
            ),
          ),
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stat(_num(record.creditsEarned),
              'credits earned${record.creditsInProgress > 0 ? ' · ${_num(record.creditsInProgress)} in progress' : ''}'),
          const SizedBox(width: 8),
          stat(record.cumulativeGpa ?? '–', 'cumulative GPA'),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _ChartCard({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _GpaCard extends StatelessWidget {
  final List<TermSummary> terms;
  const _GpaCard({required this.terms});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    final series = [
      ChartSeries('Trimester GPA', c.series1, [for (final t in terms) t.termGpa]),
      ChartSeries('Cumulative GPA', c.series2, [for (final t in terms) t.cumulativeGpa]),
    ];
    final all = [for (final s in series) ...s.values.whereType<double>()];
    // The GPA scale tops out at 5; start half a point below the lowest value
    // so differences between terms are visible.
    final low = all.isEmpty ? 0.0 : math.max(0.0, ((all.reduce(math.min) - 0.5) * 2).floor() / 2);
    final ticks = [for (var t = low; t <= 5.0001; t += (5 - low) > 2 ? 1.0 : 0.5) t];
    final latest = terms.last;

    return _ChartCard(
      title: 'GPA by term',
      subtitle: 'Tap a term for its numbers',
      children: [
        ChartLegend(series: series),
        const SizedBox(height: 8),
        LineChart(
          xLabels: [for (final t in terms) t.label],
          series: series,
          yMin: low,
          yMax: 5,
          yTicks: ticks,
          format: (v) => v.toStringAsFixed(2),
          semanticsLabel: 'GPA by term. ${[
            for (final t in terms)
              '${t.name}: trimester ${t.termGpa?.toStringAsFixed(2) ?? 'none'}, cumulative ${t.cumulativeGpa?.toStringAsFixed(2) ?? 'none'}'
          ].join('. ')}. Latest cumulative GPA ${latest.cumulativeGpa?.toStringAsFixed(2) ?? 'unknown'}.',
        ),
        ChartTable(
          headers: const ['Term', 'Trimester', 'Cumulative'],
          rows: [
            for (final t in terms)
              [t.name, t.termGpa?.toStringAsFixed(2) ?? '–', t.cumulativeGpa?.toStringAsFixed(2) ?? '–'],
          ],
        ),
      ],
    );
  }
}

class _CreditsCard extends StatelessWidget {
  final List<TermSummary> terms;
  const _CreditsCard({required this.terms});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    return _ChartCard(
      title: 'Credits earned per term',
      children: [
        ColumnChart(
          labels: [for (final t in terms) t.label],
          values: [for (final t in terms) t.creditsEarned],
          color: c.series1,
          format: _num,
          semanticsLabel:
              'Credits earned per term. ${[for (final t in terms) '${t.name}: ${_num(t.creditsEarned)}'].join('. ')}.',
        ),
        ChartTable(
          headers: const ['Term', 'Credits earned'],
          rows: [
            for (final t in terms) [t.name, _num(t.creditsEarned)],
          ],
        ),
      ],
    );
  }
}

class _GradesCard extends StatelessWidget {
  final Map<String, int> counts;
  const _GradesCard({required this.counts});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    // Only grades you've had, best first.
    final grades = gradeOrder.where((g) => (counts[g] ?? 0) > 0).toList();
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return _ChartCard(
      title: 'Grades',
      subtitle: '$total graded ${total == 1 ? 'course' : 'courses'}',
      children: [
        ColumnChart(
          labels: grades,
          values: [for (final g in grades) counts[g]!.toDouble()],
          color: c.series1,
          format: (v) => '${v.round()}',
          semanticsLabel: 'Grades. ${[for (final g in grades) '$g: ${counts[g]}'].join(', ')}.',
        ),
        ChartTable(
          headers: const ['Grade', 'Courses'],
          rows: [
            for (final g in grades) [g, '${counts[g]}'],
          ],
        ),
      ],
    );
  }
}
