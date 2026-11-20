import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/domain/updates.dart';

/// A small "3 new" chip; screen readers hear [semanticsLabel] instead.
class NewBadge extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  const NewBadge({super.key, required this.label, required this.semanticsLabel});

  /// "N new" for a course's updates, or nothing when there are none.
  static Widget forCourse(CourseUpdates? u) => u == null || u.isEmpty
      ? const SizedBox.shrink()
      : NewBadge(label: '${u.total} new', semanticsLabel: u.summary);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = Tone.info.colors(theme.colorScheme);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
