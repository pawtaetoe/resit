import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';

/// Centered icon + title + explanation + optional action. Used for empty,
/// error and signed-out states so they all look and behave the same.
class MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Tone tone;

  /// Technical text for troubleshooting, shown collapsed under the message.
  final String? detail;

  /// For use inside a list (less padding, not centred in the screen).
  final bool compact;

  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = Tone.neutral,
    this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = tone.colors(theme.colorScheme);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 36, backgroundColor: bg, child: Icon(icon, size: 36, color: fg)),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (detail != null) ...[
                const SizedBox(height: 8),
                // Kept out of the way: it's for troubleshooting, not reading.
                ExpansionTile(
                  title: Text('Technical details',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 48),
                  children: [
                    SelectableText(
                      detail!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}
