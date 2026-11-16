import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/room_booking/domain/quota.dart';

/// Weekly allowance left per room type for the week containing [day], so the
/// student sees the limit before hitting it.
class QuotaCard extends ConsumerWidget {
  final DateTime day;

  const QuotaCard({super.key, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(quotaDataProvider);
    final week = weekStart(day);
    final sunday = DateTime(week.year, week.month, week.day + 6);
    final thisWeek = week == weekStart(DateTime.now());
    final title = thisWeek
        ? 'Hours left this week'
        : 'Hours left, week of ${DateFormat('d MMM').format(week)}–${DateFormat('d MMM').format(sunday)}';

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    } else if (async.hasError && !async.hasValue) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              "Couldn't check your weekly hours. You can still book; the system enforces the limit.",
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: () => ref.invalidate(quotaDataProvider), child: const Text('Retry')),
        ],
      );
    } else {
      final quota = weeklyQuotaFor(ref, day)!;
      body = Column(
        children: [
          for (final type in quotaRoomTypes) _QuotaRow(type: type, quota: quota),
          if (quota.unknownBookings > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${quota.unknownBookings} booking(s) this week could not be matched to a room type and are not counted.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_bottom, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                Text('${formatHours(weeklyQuotaMinutes)} each',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

class _QuotaRow extends StatelessWidget {
  final String type;
  final WeeklyQuota quota;

  const _QuotaRow({required this.type, required this.quota});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final left = quota.remaining(type);
    final used = quota.used(type).clamp(0, weeklyQuotaMinutes);
    final tone = left == 0
        ? Tone.danger
        : left < 60
            ? Tone.warning
            : Tone.success;
    final (_, fg) = tone.colors(scheme);
    final barColor = left == 0
        ? scheme.error
        : left < 60
            ? fg
            : scheme.primary;

    return Semantics(
      label: '${roomTypeLabel(type)}: ${formatHours(left)} left of ${formatHours(weeklyQuotaMinutes)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(roomTypeLabel(type))),
                Text(
                  left == 0 ? 'None left' : '${formatHours(left)} left',
                  style: TextStyle(fontWeight: FontWeight.w600, color: left == 0 ? scheme.error : null),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: used / weeklyQuotaMinutes,
                minHeight: 6,
                color: barColor,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of hours left ("Discussion 2 h · Meeting 4 h") that expands to
/// the full [QuotaCard] on tap, so it doesn't push the search further down.
class QuotaSummary extends ConsumerStatefulWidget {
  final DateTime day;
  const QuotaSummary({super.key, required this.day});

  @override
  ConsumerState<QuotaSummary> createState() => _QuotaSummaryState();
}

class _QuotaSummaryState extends ConsumerState<QuotaSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quotaDataProvider);
    // Errors show the full card, which has the retry button.
    if (_expanded || (async.hasError && !async.hasValue)) {
      return GestureDetector(
        onTap: async.hasError ? null : () => setState(() => _expanded = false),
        child: QuotaCard(day: widget.day),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quota = weeklyQuotaFor(ref, widget.day);
    final thisWeek = weekStart(widget.day) == weekStart(DateTime.now());
    final parts = quota == null
        ? null
        : [
            for (final type in quotaRoomTypes)
              '${roomTypeLabel(type).replaceAll(' rooms', '')} ${formatHours(quota.remaining(type))}',
          ];
    final anyOut = quota != null && quotaRoomTypes.any((t) => quota.remaining(t) == 0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => setState(() => _expanded = true),
        dense: true,
        leading: Icon(Icons.hourglass_bottom, color: anyOut ? scheme.error : scheme.onSurfaceVariant),
        title: Text(thisWeek ? 'Hours left this week' : 'Hours left that week'),
        subtitle: parts == null
            ? const Text('Checking…')
            : Text(parts.join(' · '), style: TextStyle(color: anyOut ? scheme.error : null)),
        trailing: const Icon(Icons.expand_more),
      ),
    );
  }
}
