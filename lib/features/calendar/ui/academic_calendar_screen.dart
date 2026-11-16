import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
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
                      _NowCard(calendar: calendar, position: position, today: today),
                      const SizedBox(height: 20),
                      if (selected != null)
                        for (final term in selected.terms) ...[
                          _TermCard(term: term, today: today, initiallyExpanded: position?.term == term),
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

/// Where today is: "Week 10 · Trimester 1", progress through the trimester,
/// and the next change (recess, finals, break). Between trimesters, when the
/// next one starts.
class _NowCard extends StatelessWidget {
  final AcademicCalendar calendar;
  final CalendarPosition? position;
  final DateTime today;

  const _NowCard({required this.calendar, required this.position, required this.today});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onPrimaryContainer;
    final d = DateFormat('EEE d MMM');
    final p = position;

    final Widget content;
    if (p == null) {
      final next = calendar.nextTermAfter(today);
      content = Text(
        next == null
            ? "Today isn't covered by the published calendar."
            : 'Between trimesters. ${next.$2.name} (${next.$1.label}) starts ${d.format(next.$2.start)}.',
        style: theme.textTheme.titleMedium?.copyWith(color: fg),
      );
    } else {
      final termWeeks = p.term.termWeeks;
      final done = termWeeks.where((w) => w.end.isBefore(today)).length;
      final change = p.nextChange;
      final daysTo = change?.start.difference(DateTime(today.year, today.month, today.day)).inDays;
      final inWords = daysTo == null
          ? ''
          : daysTo < 7
              ? 'in $daysTo ${daysTo == 1 ? 'day' : 'days'}'
              : 'in ${(daysTo / 7).round()} ${(daysTo / 7).round() == 1 ? 'week' : 'weeks'}';

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: theme.textTheme.bodySmall?.copyWith(color: fg)),
          Text(
            'Week ${p.week.number}',
            style: theme.textTheme.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.bold),
          ),
          Text('${p.term.name} · ${p.year.label} · ${phaseLabel(p.week.phase)}',
              style: theme.textTheme.titleSmall?.copyWith(color: fg)),
          Text('${d.format(p.week.start)} – ${d.format(p.week.end)}',
              style: theme.textTheme.bodySmall?.copyWith(color: fg)),
          if (p.week.phase != WeekPhase.trimesterBreak) ...[
            const SizedBox(height: 12),
            Semantics(
              label: '$done of ${termWeeks.length} weeks of the trimester done',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: termWeeks.isEmpty ? 0 : done / termWeeks.length,
                  minHeight: 6,
                  backgroundColor: fg.withValues(alpha: 0.15),
                  color: fg,
                ),
              ),
            ),
          ],
          if (change != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: fg),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${phaseLabel(change.phase)} from ${d.format(change.start)} ($inWords)',
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ],
          if (p.week.hasHoliday) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.celebration_outlined, size: 18, color: fg),
                const SizedBox(width: 6),
                Text('Public holiday this week', style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
              ],
            ),
          ],
        ],
      );
    }

    return TintedCard(color: scheme.primaryContainer, child: content);
  }
}

class _TermCard extends StatelessWidget {
  final AcademicTerm term;
  final DateTime today;
  final bool initiallyExpanded;

  const _TermCard({required this.term, required this.today, required this.initiallyExpanded});

  @override
  Widget build(BuildContext context) {
    final d = DateFormat('d MMM');
    final finals = term.weeks.where((w) => w.phase == WeekPhase.finals).firstOrNull;
    final recess = term.weeks.where((w) => w.phase == WeekPhase.recess).firstOrNull;
    final summary = [
      '${d.format(term.start)} – ${d.format(term.end)}',
      if (recess != null) 'recess ${d.format(recess.start)}',
      if (finals != null) 'finals ${d.format(finals.start)}',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text('${term.name} · ${term.start.year}', style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(summary),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [for (final w in term.weeks) _WeekRow(week: w, isNow: w.contains(today))],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final AcademicWeek week;
  final bool isNow;

  const _WeekRow({required this.week, required this.isNow});

  Tone get _tone => switch (week.phase) {
        WeekPhase.recess => Tone.info,
        WeekPhase.finals => Tone.danger,
        WeekPhase.trimesterBreak => Tone.success,
        _ => Tone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = DateFormat('d MMM');
    final holiday = [
      if (week.holidayWeekday) 'public holiday on a weekday',
      if (week.holidayWeekendOrMonday) 'public holiday on a weekend or Monday',
    ].join(' and ');

    return Semantics(
      label: 'Week ${week.number}, ${d.format(week.start)} to ${d.format(week.end)}, ${phaseLabel(week.phase)}'
          '${holiday.isEmpty ? '' : ', $holiday'}${isNow ? ', this week' : ''}',
      excludeSemantics: true,
      child: Container(
        color: isNow ? scheme.secondaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text('Wk ${week.number}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: isNow ? FontWeight.bold : null)),
            ),
            Expanded(
              child: Text('${d.format(week.start)} – ${d.format(week.end)}',
                  style: TextStyle(fontWeight: isNow ? FontWeight.bold : null)),
            ),
            // Spelled out, not an icon you'd have to long-press to understand.
            if (week.hasHoliday)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: holiday,
                  child: const StatusPill(label: 'PH', tone: Tone.warning, icon: Icons.celebration_outlined),
                ),
              ),
            if (week.phase != WeekPhase.study) StatusPill(label: phaseLabel(week.phase), tone: _tone),
          ],
        ),
      ),
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
