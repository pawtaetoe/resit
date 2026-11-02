import 'dart:math' as math;

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
                  painter: _LinePainter(widget, layout, colors, text, selected),
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

  _LinePainter(this.chart, this.l, this.c, this.text, this.selected);

  void _text(Canvas canvas, String s, Offset at, TextStyle? style,
      {TextAlign align = TextAlign.left, bool middle = true}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
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
    final small = text.bodySmall?.copyWith(color: c.mutedText, fontSize: 11);

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
  bool shouldRepaint(_LinePainter old) => old.selected != selected || old.chart != chart || old.c.surface != c.surface;
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

/// A column chart for one series of magnitudes (e.g. credits per term).
/// Columns are at most 24 px wide with 4 px rounded tops, grow from a zero
/// baseline, and carry their value on the cap.
class ColumnChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final Color color;
  final String Function(double) format;
  final String semanticsLabel;
  final double height;

  const ColumnChart({
    super.key,
    required this.labels,
    required this.values,
    required this.color,
    required this.format,
    required this.semanticsLabel,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ChartColors.of(context);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _ColumnPainter(this, colors, Theme.of(context).textTheme)),
      ),
    );
  }
}

class _ColumnPainter extends CustomPainter {
  final ColumnChart chart;
  final ChartColors c;
  final TextTheme text;

  _ColumnPainter(this.chart, this.c, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    const top = 18.0, bottom = 24.0;
    final n = chart.values.length;
    if (n == 0) return;
    final maxV = chart.values.fold<double>(0, math.max);
    final plotH = size.height - top - bottom;
    final band = size.width / n;
    final barW = math.min(24.0, band * 0.6);
    final baseY = size.height - bottom;
    final small = text.bodySmall?.copyWith(color: c.mutedText, fontSize: 11);
    final value = text.bodySmall?.copyWith(color: c.text, fontWeight: FontWeight.w600, fontSize: 11);

    // Baseline hairline.
    canvas.drawLine(
        Offset(0, baseY),
        Offset(size.width, baseY),
        Paint()
          ..color = c.grid
          ..strokeWidth = 1);

    for (var i = 0; i < n; i++) {
      final v = chart.values[i];
      final h = maxV <= 0 ? 0.0 : plotH * v / maxV;
      final cx = band * i + band / 2;
      if (h > 0) {
        final rect = Rect.fromLTWH(cx - barW / 2, baseY - h, barW, h);
        // Rounded at the data end, square at the baseline.
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = chart.color,
        );
      }
      _paint(canvas, chart.format(v), Offset(cx, baseY - h - 4), value, above: true);
      _paint(canvas, chart.labels[i], Offset(cx, baseY + 6), small, above: false);
    }
  }

  void _paint(Canvas canvas, String s, Offset at, TextStyle? style, {required bool above}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, above ? at.dy - tp.height : at.dy));
  }

  @override
  bool shouldRepaint(_ColumnPainter old) => old.chart != chart || old.c.series1 != c.series1;
}

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
      shape: const Border(),
      collapsedShape: const Border(),
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
