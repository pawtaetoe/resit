import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/widgets/thumb_bar.dart';

/// Whether grades and GPAs are shown. Hidden each time the app starts, so
/// they aren't on screen for anyone looking over the user's shoulder; one
/// tap on any eye button shows them everywhere until the app is closed.
final gradesVisibleProvider = StateProvider<bool>((ref) => false);

/// What a hidden grade or GPA shows instead of its value.
const hiddenValue = '•••';

/// The eye button that shows or hides grades. Closed eye while hidden.
class GradeVisibilityButton extends ConsumerWidget {
  /// Bar style: an outlined square the height of a [ThumbBar]'s controls.
  final bool inBar;
  final Color? color;

  const GradeVisibilityButton({super.key, this.inBar = false, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(gradesVisibleProvider);
    void toggle() => ref.read(gradesVisibleProvider.notifier).state = !visible;
    final icon = Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: color);
    final tooltip = visible ? 'Hide grades' : 'Show grades';

    if (inBar) {
      return SizedBox.square(
        dimension: ThumbBar.heightOf(context),
        child: IconButton.outlined(
          tooltip: tooltip,
          isSelected: visible,
          style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: toggle,
          icon: icon,
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: toggle,
      icon: icon,
    );
  }
}

/// Covers a block of grades (e.g. a chart) while grades are hidden: blurred,
/// with a closed eye and "Tap to show". Screen readers hear only that it's
/// hidden, not the numbers underneath.
class GradeCurtain extends ConsumerWidget {
  final Widget child;
  const GradeCurtain({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(gradesVisibleProvider)) return child;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Grades hidden. Show grades',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(gradesVisibleProvider.notifier).state = true,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Blurred and faded, so the shape of the data doesn't show.
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.decal),
              child: Opacity(opacity: 0.35, child: IgnorePointer(child: child)),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_off_outlined, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text('Grades hidden · tap to show',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
