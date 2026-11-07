import 'package:flutter/material.dart';

/// A small heading above a group of cards (primary colour), or above a form
/// field ([muted]). [trailing] sits at the right end, e.g. a show/hide button.
class SectionLabel extends StatelessWidget {
  final String text;
  final bool muted;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.muted = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      text,
      style: theme.textTheme.titleSmall
          ?.copyWith(color: muted ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary),
    );
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: trailing == null ? 8 : 0),
      child: trailing == null
          ? label
          : Row(children: [Expanded(child: Semantics(header: true, child: label)), trailing!]),
    );
  }
}
