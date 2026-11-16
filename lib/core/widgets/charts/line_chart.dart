import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/charts/chart_series.dart';
import 'package:resit/core/widgets/charts/chart_text_scale.dart';

/// A line chart over categories (e.g. terms), one shared y-axis. Tap or drag
/// to show a crosshair with each series' value. The last value of each line
/// is labelled at its end; axis ticks carry the rest.
class LineChart extends StatefulWidget {
  final List<String> xLabels;
  final List<ChartSeries> series;
  final double yMin;
  final double yMax;
  final List<double> yTicks;
  final String Function(double) format;
  final String semanticsLabel;
  final double height;

  const LineChart({
    super.key,
    required this.xLabels,
    required this.series,
    required this.yMin,
    required this.yMax,
    required this.yTicks,
    required this.format,
    required this.semanticsLabel,
    this.height = 200,
  });

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _selected;

  void _select(Offset local, Size size, _LineLayout layout) {
    final i = layout.indexAt(local.dx);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ChartColors.of(context);
    final text = Theme.of(context).textTheme;

    return Semantics(
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          final layout = _LineLayout(size, widget.xLabels.length, widget.yMin, widget.yMax);
          final selected = _selected;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _select(d.localPosition, size, layout),
            onHorizontalDragUpdate: (d) => _select(d.localPosition, size, layout),
            onTapUp: (_) {},
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: size,
                  painter: _LinePainter(widget, layout, colors, text, selected, chartTextScale(context)),
                ),
                if (selected != null)
                  Positioned(
                    top: 0,
                    left: (layout.x(selected) - 70).clamp(0.0, math.max(0.0, size.width - 140)),
                    width: 140,
                    child: _Tooltip(
                      title: widget.xLabels[selected],
                      rows: [
                        for (final s in widget.series)
                          if (s.values[selected] != null) (s.color, s.name, widget.format(s.values[selected]!)),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _LineLayout {
  static const left = 34.0, right = 40.0, top = 12.0, bottom = 24.0;
  final Size size;
  final int count;
  final double yMin, yMax;

  _LineLayout(this.size, this.count, this.yMin, this.yMax);

  double get plotWidth => size.width - left - right;
  double get plotHeight => size.height - top - bottom;

  double x(int i) => count <= 1 ? left + plotWidth / 2 : left + plotWidth * i / (count - 1);
  double y(double v) => top + plotHeight * (1 - (v - yMin) / (yMax - yMin));

  int? indexAt(double dx) {
    if (count == 0) return null;
    var best = 0;
    for (var i = 1; i < count; i++) {
      if ((x(i) - dx).abs() < (x(best) - dx).abs()) best = i;
    }
    return best;
  }
}

class _LinePainter extends CustomPainter {
  final LineChart chart;
  final _LineLayout l;
  final ChartColors c;
  final TextTheme text;
  final int? selected;
  final TextScaler scale;

  _LinePainter(this.chart, this.l, this.c, this.text, this.selected, this.scale);

  void _text(Canvas canvas, String s, Offset at, TextStyle? style,
      {TextAlign align = TextAlign.left, bool middle = true}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scale)
      ..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, middle ? at.dy - tp.height / 2 : at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = c.grid
      ..strokeWidth = 1;
    final small = text.labelSmall?.copyWith(color: c.mutedText);

    // Hairline gridlines and y-axis ticks.
    for (final t in chart.yTicks) {
      final y = l.y(t);
      canvas.drawLine(Offset(_LineLayout.left, y), Offset(size.width - _LineLayout.right, y), grid);
      _text(canvas, chart.format(t), Offset(_LineLayout.left - 6, y), small, align: TextAlign.right);
    }

    // X labels: all if they fit, otherwise every other one.
    final step = chart.xLabels.length > 6 ? 2 : 1;
    for (var i = 0; i < chart.xLabels.length; i += step) {
      _text(canvas, chart.xLabels[i], Offset(l.x(i), size.height - _LineLayout.bottom + 6), small,
          align: TextAlign.center, middle: false);
    }

    // Crosshair for the selected term.
    if (selected != null) {
      canvas.drawLine(Offset(l.x(selected!), _LineLayout.top), Offset(l.x(selected!), size.height - _LineLayout.bottom),
          grid..color = c.mutedText.withValues(alpha: 0.5));
    }

    for (final s in chart.series) {
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var started = false;
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) {
          started = false;
          continue;
        }
        final p = Offset(l.x(i), l.y(v));
        started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        started = true;
      }
      canvas.drawPath(path, line);

      // Points: 8 px, with a 2 px ring in the surface colour.
      for (var i = 0; i < s.values.length; i++) {
        final v = s.values[i];
        if (v == null) continue;
        final p = Offset(l.x(i), l.y(v));
        final r = i == selected ? 5.0 : 4.0;
        canvas.drawCircle(p, r + 2, Paint()..color = c.surface);
        canvas.drawCircle(p, r, Paint()..color = s.color);
      }
    }

    // End labels: the latest value of each line, in text colour, nudged
    // apart if they'd overlap.
    final ends = <(double, String)>[];
    for (final s in chart.series) {
      final last = s.values.lastIndexWhere((v) => v != null);
      if (last >= 0) ends.add((l.y(s.values[last]!), chart.format(s.values[last]!)));
    }
    ends.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < ends.length; i++) {
      if (ends[i].$1 - ends[i - 1].$1 < 14) ends[i] = (ends[i - 1].$1 + 14, ends[i].$2);
    }
    final endX = l.x(chart.xLabels.length - 1) + 8;
    for (final (y, label) in ends) {
      _text(canvas, label, Offset(endX, y), text.bodySmall?.copyWith(color: c.text, fontWeight: FontWeight.w600));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.selected != selected ||
      old.c.surface != c.surface ||
      old.scale != scale ||
      !listEquals(old.chart.xLabels, chart.xLabels) ||
      old.chart.series.length != chart.series.length ||
      [for (var i = 0; i < chart.series.length; i++) !listEquals(old.chart.series[i].values, chart.series[i].values)]
          .any((changed) => changed);
}

class _Tooltip extends StatelessWidget {
  final String title;
  final List<(Color, String, String)> rows;
  const _Tooltip({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.inverseSurface,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.bold)),
            for (final (color, name, value) in rows)
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(name,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onInverseSurface)),
                  ),
                  Text(value,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.bold)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
