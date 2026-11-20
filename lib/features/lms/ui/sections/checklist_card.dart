import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

/// A checklist: its description, then each category's items with any due
/// date. Starts open; tapping the header opens it on xSiTe (where ticks are
/// kept).
class ChecklistCard extends StatelessWidget {
  final Checklist checklist;
  final DateTime now;
  const ChecklistCard({super.key, required this.checklist, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = checklist;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(Icons.checklist, color: theme.colorScheme.primary),
          title: Text(c.name, style: theme.textTheme.titleMedium),
          subtitle: Text('${c.itemCount} item${c.itemCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          childrenPadding: const EdgeInsets.fromLTRB(Space.inset, 0, Space.inset, Space.dense),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.description.isNotEmpty) ...[MoreText(c.description, lines: 3), const SizedBox(height: 8)],
            for (final cat in c.categories) ...[
              if (cat.name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(cat.name, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                ),
              if (cat.description.isNotEmpty)
                Text(cat.description, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              for (final item in cat.items) _ItemRow(item: item, now: now),
            ],
            if (c.itemCount == 0)
              Text('No items to show.', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openInBrowser(context, c.url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Tick items on xSiTe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ChecklistItem item;
  final DateTime now;
  const _ItemRow({required this.item, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = item.dueDate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(Icons.fiber_manual_record, size: 8, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: theme.textTheme.bodyLarge),
                if (item.description.isNotEmpty) MoreText(item.description, lines: 2),
                if (due != null) ...[
                  const SizedBox(height: 4),
                  StatusPill(label: dueLabel(due, now), tone: dueTone(due, now), icon: Icons.schedule),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
