import 'package:flutter/material.dart';

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
