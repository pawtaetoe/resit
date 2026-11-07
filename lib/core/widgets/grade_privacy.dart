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
      return ThumbIconButton(
        tooltip: tooltip,
        icon: Icons.visibility_off_outlined,
        selectedIcon: Icons.visibility_outlined,
        selected: visible,
        onPressed: toggle,
      );
    }
    // Full 48 px target.
    return IconButton(tooltip: tooltip, onPressed: toggle, icon: icon);
  }
}

/// Covers a block of grades (e.g. a chart) while grades are hidden: the
/// block keeps its size but isn't drawn, with a closed eye and "tap to show"
/// in its place. Screen readers hear only that it's hidden.
class GradeCurtain extends ConsumerWidget {
  final Widget child;
  const GradeCurtain({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(gradesVisibleProvider)) return child;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
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
            // Laid out (so the card keeps its height) but never painted:
            // nothing of the data shows, and there's no blur to redraw.
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: IgnorePointer(child: child),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_off_outlined, color: muted),
                const SizedBox(height: 4),
                Text('Grades hidden · tap to show', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
