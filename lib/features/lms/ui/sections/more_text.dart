import 'package:flutter/material.dart';

/// Text that shows a few lines and expands on tap.
class MoreText extends StatefulWidget {
  final String text;
  final int lines;
  const MoreText(this.text, {super.key, this.lines = 4});

  @override
  State<MoreText> createState() => _MoreTextState();
}

class _MoreTextState extends State<MoreText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.text,
              maxLines: _open ? null : widget.lines, overflow: _open ? null : TextOverflow.ellipsis),
          if (widget.text.split('\n').length > widget.lines || widget.text.length > widget.lines * 60)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_open ? 'Show less' : 'Show more',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            ),
        ],
      ),
    );
  }
}
