import 'package:flutter/material.dart';
import 'package:resit/core/widgets/desktop/desktop_scope.dart';

/// Bottom bar for screens opened from Home, so back and the screen's main
/// actions sit where a thumb reaches when the phone is held in one hand.
/// Shows a back button when there's somewhere to go back to, then [child].
class ThumbBar extends StatelessWidget {
  /// Every control in the bar is this tall (at normal text size), so back
  /// and the actions line up.
  static const height = 52.0;

  /// The bar's control height for the user's text size: it grows with larger
  /// system fonts (up to 80 px) so labels aren't clipped.
  static double heightOf(BuildContext context) => DesktopScope.of(context)
      // Desktop: a compact toolbar for the mouse.
      ? MediaQuery.textScalerOf(context).scale(40).clamp(40.0, 64.0)
      : MediaQuery.textScalerOf(context).scale(height).clamp(height, 80.0);

  final Widget? child;

  /// Optional line of context shown above the controls, across the full width
  /// (e.g. the date and time being searched).
  final Widget? caption;

  const ThumbBar({super.key, this.child, this.caption});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();
    final height = heightOf(context);

    return Material(
      color: scheme.surfaceContainer,
      // A hairline on top, so a bar above the tab bar (Account) doesn't merge with it.
      shape: Border(top: BorderSide(color: scheme.outlineVariant)),
      child: SafeArea(
        top: false,
        // On wide screens the controls stop at 640 px and centre, rather than
        // stretching a button across a desktop window.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (caption != null) ...[
                    DefaultTextStyle.merge(
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                      child: caption!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (canPop)
                          ThumbIconButton(
                            tooltip: 'Back',
                            icon: Icons.arrow_back,
                            tonal: true,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        if (canPop && child != null) const SizedBox(width: 12),
                        if (child != null) Expanded(child: child!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A square icon button the height of a [ThumbBar]'s controls, with the
/// same rounded corners as its other buttons. Outlined by default; [tonal]
/// for back. [selected] shows the filled look for an on/off button.
class ThumbIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final IconData? selectedIcon;
  final VoidCallback? onPressed;
  final bool tonal;
  final bool? selected;

  const ThumbIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selectedIcon,
    this.tonal = false,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final style = IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
    final i = Icon(icon);
    final si = selectedIcon == null ? null : Icon(selectedIcon);
    return SizedBox.square(
      dimension: ThumbBar.heightOf(context),
      child: tonal
          ? IconButton.filledTonal(
              tooltip: tooltip, style: style, isSelected: selected, onPressed: onPressed, icon: i, selectedIcon: si)
          : IconButton.outlined(
              tooltip: tooltip, style: style, isSelected: selected, onPressed: onPressed, icon: i, selectedIcon: si),
    );
  }
}
