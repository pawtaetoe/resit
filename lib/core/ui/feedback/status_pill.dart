import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';

/// Small tinted label, e.g. a booking status.
class StatusPill extends StatelessWidget {
  final String label;
  final Tone tone;
  final IconData? icon;

  const StatusPill({super.key, required this.label, required this.tone, this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
