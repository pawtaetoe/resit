import 'package:flutter/material.dart';
import 'package:resit/features/timetable/ui/course_palette.dart';

/// Which colour is which module: a swatch and code for each of [codes], in
/// a row that scrolls sideways when it doesn't fit.
class ModuleLegend extends StatelessWidget {
  final Iterable<String> codes;
  final CoursePalette palette;

  const ModuleLegend({super.key, required this.codes, required this.palette});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall;
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final code in codes)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: palette.colourOf(code), borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 6),
                  Text(code, style: small?.copyWith(color: theme.colorScheme.onSurface)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
