import 'package:flutter/material.dart';

/// Bottom bar for screens opened from Home, so back and the screen's main
/// actions sit where a thumb reaches when the phone is held in one hand.
/// Shows a back button when there's somewhere to go back to, then [child].
class ThumbBar extends StatelessWidget {
  /// Every control in the bar is this tall (at normal text size), so back
  /// and the actions line up.
  static const height = 52.0;

  /// The bar's control height for the user's text size: it grows with larger
  /// system fonts (up to 80 px) so labels aren't clipped.
  static double heightOf(BuildContext context) => MediaQuery.textScalerOf(context).scale(height).clamp(height, 80.0);

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

/// One option of a [ThumbToggle].
class ThumbToggleOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const ThumbToggleOption(this.value, this.label, {this.icon});
}

/// A two-or-more option switch for a [ThumbBar]: fills the bar's 52 px height
/// exactly, with the same rounded corners as its buttons, on every platform.
class ThumbToggle<T> extends StatelessWidget {
  final List<ThumbToggleOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const ThumbToggle({super.key, required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);

    return Container(
      height: ThumbBar.heightOf(context),
      decoration: BoxDecoration(border: Border.all(color: scheme.outline), borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, thickness: 1, color: scheme.outline),
              Expanded(child: _segment(context, options[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, ThumbToggleOption<T> option) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = option.value == selected;
    final fg = on ? scheme.onSecondaryContainer : scheme.onSurface;

    return Semantics(
      button: true,
      selected: on,
      child: Material(
        color: on ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: on ? null : () => onChanged(option.value),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (option.icon != null) ...[Icon(option.icon, size: 18, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title-only app bar for screens that use [ThumbBar]: back lives at the
/// bottom, so it isn't repeated in the hard-to-reach top corner. [subtitle]
/// is one muted line under the title.
AppBar thumbAppBar(String title, {String? subtitle}) => AppBar(
      automaticallyImplyLeading: false,
      title: subtitle == null
          ? Text(title)
          : Builder(builder: (context) {
              final theme = Theme.of(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              );
            }),
    );

/// A choice in [showChoiceSheet].
class SheetChoice<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool primary;
  final bool danger;

  const SheetChoice(this.value, this.label, {this.icon, this.primary = false, this.danger = false});
}

/// Confirmation as a bottom sheet instead of a centred dialog: the buttons
/// end up under the thumb. Returns the chosen value, or null if dismissed.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  String? message,
  IconData? icon,
  required List<SheetChoice<T>> choices,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 32, color: scheme.primary),
                const SizedBox(height: 12),
              ],
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),
              for (final c in choices) ...[
                _choiceButton(context, c),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _choiceButton<T>(BuildContext context, SheetChoice<T> c) {
  final scheme = Theme.of(context).colorScheme;
  void pick() => Navigator.pop(context, c.value);
  final label = Text(c.label);
  final icon = c.icon == null ? null : Icon(c.icon);

  if (c.primary) {
    final style =
        c.danger ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null;
    return icon == null
        ? FilledButton(style: style, onPressed: pick, child: label)
        : FilledButton.icon(style: style, onPressed: pick, icon: icon, label: label);
  }
  final style = c.danger ? OutlinedButton.styleFrom(foregroundColor: scheme.error) : null;
  return icon == null
      ? OutlinedButton(style: style, onPressed: pick, child: label)
      : OutlinedButton.icon(style: style, onPressed: pick, icon: icon, label: label);
}
