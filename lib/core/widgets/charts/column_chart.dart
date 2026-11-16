import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/charts/chart_text_scale.dart';

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
        child: CustomPaint(
            painter: _ColumnPainter(this, colors, Theme.of(context).textTheme, chartTextScale(context))),
      ),
    );
  }
}

class _ColumnPainter extends CustomPainter {
  final ColumnChart chart;
  final ChartColors c;
  final TextTheme text;
  final TextScaler scale;

  _ColumnPainter(this.chart, this.c, this.text, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    const top = 18.0, bottom = 24.0;
    final n = chart.values.length;
    if (n == 0) return;
    final maxV = chart.values.fold<double>(0, math.max);
    final plotH = size.height - top - bottom;
    final band = size.width / n;
    final barW = math.min(40.0, band * 0.6);
    final baseY = size.height - bottom;
    final small = text.labelSmall?.copyWith(color: c.mutedText);
    final value = text.labelSmall?.copyWith(color: c.text, fontWeight: FontWeight.w600);

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
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scale)
      ..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, above ? at.dy - tp.height : at.dy));
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.c.series1 != c.series1 ||
      old.scale != scale ||
      !listEquals(old.chart.values, chart.values) ||
      !listEquals(old.chart.labels, chart.labels);
}
