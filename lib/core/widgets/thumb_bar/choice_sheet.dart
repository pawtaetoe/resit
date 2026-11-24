import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';

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
  final style = c.danger ? dangerTonal(scheme) : null;
  return icon == null
      ? FilledButton.tonal(style: style, onPressed: pick, child: label)
      : FilledButton.tonalIcon(style: style, onPressed: pick, icon: icon, label: label);
}
