import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';

/// One line in a [LineChart]. Null values are gaps.
class ChartSeries {
  final String name;
  final Color color;
  final List<double?> values;

  const ChartSeries(this.name, this.color, this.values);
}

/// A legend: a swatch and name per series. Shown for two or more series, so
/// identity never relies on colour alone.
class ChartLegend extends StatelessWidget {
  final List<ChartSeries> series;
  const ChartLegend({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final s in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(s.name, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text)),
            ],
          ),
      ],
    );
  }
}
