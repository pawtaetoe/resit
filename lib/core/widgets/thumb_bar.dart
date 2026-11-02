import 'package:flutter/material.dart';

/// Bottom bar for screens opened from Home, so back and the screen's main
/// actions sit where a thumb reaches when the phone is held in one hand.
/// Shows a back button when there's somewhere to go back to, then [child].
class ThumbBar extends StatelessWidget {
  final Widget? child;

  const ThumbBar({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              if (canPop)
                IconButton.filledTonal(
                  tooltip: 'Back',
                  iconSize: 24,
                  style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
              if (canPop && child != null) const SizedBox(width: 12),
              if (child != null) Expanded(child: child!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title-only app bar for screens that use [ThumbBar]: back lives at the
/// bottom, so it isn't repeated in the hard-to-reach top corner.
AppBar thumbAppBar(String title, {Widget? subtitle}) => AppBar(
      automaticallyImplyLeading: false,
      title: subtitle == null
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(title), subtitle],
            ),
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
