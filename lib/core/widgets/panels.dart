import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';

/// A filled panel in a theme colour (e.g. primaryContainer), without the
/// hairline border plain cards have. Use for hero and stat panels so they
/// all look the same.
class TintedCard extends StatelessWidget {
  final Color color;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const TintedCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.inset),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A status or notice strip: icon, title, optional message and action, in a
/// [Tone]'s colours. Used for sign-in status, "results not out yet", refresh
/// failures, rooms that couldn't be checked, and so on.
class StatusBanner extends StatelessWidget {
  final Tone tone;
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const StatusBanner({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = tone.colors(theme.colorScheme);
    return Semantics(
      container: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.inset, 14, 8, 14),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: Space.dense),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                    if (message != null) ...[
                      const SizedBox(height: 2),
                      Text(message!, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
                    ],
                  ],
                ),
              ),
              if (action != null)
                TextButtonTheme(
                  data: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: fg)),
                  child: action!,
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number with a caption under it (credits, GPA, countdowns). Same layout
/// everywhere: optional icon, big value, small caption.
class StatTile extends StatelessWidget {
  final String value;
  final String caption;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Read out instead of "value, caption" (e.g. when the value is hidden).
  final String? semanticsLabel;

  /// Highlighted (primaryContainer) instead of a plain card.
  final bool tinted;

  const StatTile({
    super.key,
    required this.value,
    required this.caption,
    this.icon,
    this.onTap,
    this.semanticsLabel,
    this.tinted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = tinted ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = tinted ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final content = Semantics(
      label: semanticsLabel ?? '$value, $caption',
      button: onTap != null,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: tinted ? fg : scheme.primary),
            const SizedBox(height: 8),
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
    if (tinted) {
      return TintedCard(color: scheme.primaryContainer, onTap: onTap, child: content);
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(Space.inset), child: content)),
    );
  }
}

/// A thin progress line across the top of a screen while it refreshes data
/// it is already showing. Keeps its height when idle, so content doesn't jump.
class RefreshStrip extends StatelessWidget {
  final bool active;
  const RefreshStrip({super.key, required this.active});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 3,
        child: active ? const LinearProgressIndicator(minHeight: 3) : null,
      );
}

/// "Updated 2 h ago": how fresh saved data is.
String updatedAgo(DateTime when, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(when);
  if (d.inMinutes < 1) return 'Updated just now';
  if (d.inMinutes < 60) return 'Updated ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Updated ${d.inHours} h ago';
  final days = d.inDays;
  return 'Updated ${days == 1 ? 'yesterday' : '$days days ago'}';
}
