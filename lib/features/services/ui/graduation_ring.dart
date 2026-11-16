import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/panels.dart';

/// Days to the last day of school (the last day of finals) in the middle of a ring that fills as time passes,
/// from the start of the programme to graduation day.
class GraduationRing extends StatelessWidget {
  final DateTime date;
  final DateTime start;
  final bool estimated;
  final VoidCallback onTap;

  const GraduationRing({
    super.key,
    required this.date,
    required this.start,
    required this.estimated,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onPrimaryContainer;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = date.difference(today).inDays;
    final total = date.difference(start).inDays;
    final done = total <= 0 ? 1.0 : (today.difference(start).inDays / total).clamp(0.0, 1.0);
    final ringSize = MediaQuery.textScalerOf(context).scale(96).clamp(96.0, 140.0);
    final caption = days <= 0
        ? 'Finals are over!'
        : '${(done * 100).round()}% of the way · last final ${DateFormat('EEE d MMM yyyy').format(date)}'
            '${estimated ? ' (estimated)' : ''}';

    return Semantics(
      button: true,
      label: days <= 0 ? 'Finals are over' : '$days days to the last day of school, $caption',
      excludeSemantics: true,
      child: TintedCard(
        color: scheme.primaryContainer,
        onTap: onTap,
        child: Row(
          children: [
            SizedBox.square(
              dimension: ringSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: done,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: scheme.primary,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          child: Text(days <= 0 ? '🎓' : '$days',
                              style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                        ),
                        if (days > 0) Text(days == 1 ? 'day' : 'days', style: theme.textTheme.labelSmall?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.inset),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('to last day of school', style: theme.textTheme.titleMedium?.copyWith(color: fg)),
                  const SizedBox(height: 4),
                  Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: fg),
          ],
        ),
      ),
    );
  }
}
