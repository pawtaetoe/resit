import 'package:flutter/material.dart';
import 'package:resit/core/widgets/thumb_bar/thumb_bar.dart';

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
