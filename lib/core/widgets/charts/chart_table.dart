import 'package:flutter/material.dart';

/// "Show as table": the chart's numbers as rows, so nothing depends on
/// reading the chart.
class ChartTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  const ChartTable({super.key, required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ExpansionTile(
      title: Text('Show as table', style: theme.textTheme.bodyMedium),
      tilePadding: EdgeInsets.zero,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(2)},
          children: [
            TableRow(children: [
              for (final h in headers) Padding(padding: const EdgeInsets.all(4), child: Text(h, style: muted))
            ]),
            for (final r in rows)
              TableRow(children: [for (final cell in r) Padding(padding: const EdgeInsets.all(4), child: Text(cell))]),
          ],
        ),
      ],
    );
  }
}
