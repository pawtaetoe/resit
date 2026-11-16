import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:resit/features/calendar/ui/academic_term_card.dart';
import 'package:resit/features/calendar/ui/calendar_now_card.dart';
import 'package:resit/core/widgets/desktop.dart';

/// SIT's academic calendar: where today sits (week, trimester, what's next),
/// then every trimester of the chosen academic year, week by week.
class AcademicCalendarScreen extends ConsumerStatefulWidget {
  const AcademicCalendarScreen({super.key});

  @override
  ConsumerState<AcademicCalendarScreen> createState() => _AcademicCalendarScreenState();
}

class _AcademicCalendarScreenState extends ConsumerState<AcademicCalendarScreen> {
  String? _yearLabel;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await ref.read(academicCalendarServiceProvider).load(force: true);
      ref.invalidate(academicCalendarProvider);
      await ref.read(academicCalendarProvider.future);
    } catch (e) {
      if (mounted) showError(context, "Couldn't update the calendar: ${friendlyError(e)}");
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(academicCalendarProvider);
    final calendar = async.valueOrNull;
    final today = DateTime.now();
    final position = calendar?.positionOf(today);
    final years = calendar?.years ?? const <AcademicYear>[];
    final selected = years.where((y) => y.label == _yearLabel).firstOrNull ?? position?.year ?? years.lastOrNull;

    return AppScaffold(
      appBar: thumbAppBar('Academic calendar'),
      // Switch academic year under the thumb.
      bottomNavigationBar: ThumbBar(
        child: years.length < 2 || selected == null
            ? null
            : ThumbToggle<String>(
                options: [for (final y in years) ThumbToggleOption(y.label, y.label)],
                selected: selected.label,
                onChanged: (label) => setState(() => _yearLabel = label),
              ),
      ),
      body: calendar == null
          ? (async.hasError
              ? MessageView(
                  icon: Icons.cloud_off,
                  tone: Tone.danger,
                  title: "Couldn't load the calendar",
                  message: friendlyError(async.error!),
                  action: FilledButton.icon(
                    onPressed: () => ref.invalidate(academicCalendarProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                )
              : const MessageView(
                  icon: Icons.calendar_month_outlined,
                  title: 'Getting the academic calendar…',
                  message: "From SIT's website.",
                  action: SizedBox(width: 160, child: LinearProgressIndicator()),
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
                      CalendarNowCard(calendar: calendar, position: position, today: today),
                      const SizedBox(height: 20),
                      if (selected != null)
                        for (final term in selected.terms) ...[
                          AcademicTermCard(term: term, today: today, initiallyExpanded: position?.term == term),
                          const SizedBox(height: 8),
                        ],
                      const SizedBox(height: 8),
                      _Footnote(fetchedAt: calendar.fetchedAt),
                    ],
                  ),
                ),
              ),
            ]),
    );
  }
}

class _Footnote extends StatelessWidget {
  final DateTime fetchedAt;
  const _Footnote({required this.fetchedAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.celebration_outlined, size: 16, color: theme.colorScheme.tertiary),
            const SizedBox(width: 6),
            Expanded(child: Text('Week with a public holiday', style: muted)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          "From SIT's academic calendar, updated ${DateFormat('d MMM, HH:mm').format(fetchedAt)}. "
          'Dates may change; pull down to check for updates.',
          style: muted,
        ),
      ],
    );
  }
}
