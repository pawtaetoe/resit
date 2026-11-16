import 'package:flutter/material.dart';

/// Button that shows a spinner and a "doing it" label while busy, so the
/// user sees the tap registered and can't fire it twice.
class BusyButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;
  final String label;
  final String busyLabel;
  final IconData? icon;
  final bool danger;

  const BusyButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.busyLabel,
    this.busy = false,
    this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = danger
        ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
        : null;
    return FilledButton(
      style: style,
      onPressed: busy ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          const SizedBox(width: 10),
          Text(busy ? busyLabel : label),
        ],
      ),
    );
  }
}
