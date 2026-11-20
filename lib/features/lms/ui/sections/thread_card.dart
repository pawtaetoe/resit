import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/domain/discussions.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

String postDate(DateTime d) => DateFormat('d MMM yyyy, HH:mm').format(d);

/// A thread: its first post, with the replies indented under it by how
/// deep they sit.
class ThreadCard extends StatelessWidget {
  final DiscussionThread thread;
  const ThreadCard({super.key, required this.thread});

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    // "Re: <first subject>" says nothing new under the first post.
    final echo = 're: ${thread.first.subject.toLowerCase()}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostView(post: thread.first, first: true),
              for (final r in thread.replies)
                Padding(
                  padding: EdgeInsets.only(top: 12, left: 12.0 * (min(r.depth, 4) - 1)),
                  child: Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: line, width: 2))),
                    child: PostView(
                      post: r.post,
                      showSubject: r.post.subject.isNotEmpty && !r.post.subject.toLowerCase().startsWith(echo),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One post: subject, who and when, and its text (long ones collapsed).
class PostView extends StatelessWidget {
  final DiscussionPost post;
  final bool first;
  final bool showSubject;
  const PostView({super.key, required this.post, this.first = false, this.showSubject = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final byline = [if (post.author.isNotEmpty) post.author, if (post.date != null) postDate(post.date!)].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: showSubject && post.subject.isNotEmpty
                  ? Text(post.subject, style: first ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)
                  : Text(byline, style: theme.textTheme.labelLarge),
            ),
            if (post.isUnread) const StatusPill(label: 'New', tone: Tone.info),
          ],
        ),
        if (showSubject && post.subject.isNotEmpty && byline.isNotEmpty)
          Text(byline, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        if (post.body.isNotEmpty) ...[const SizedBox(height: 6), MoreText(post.body, lines: first ? 4 : 3)],
        if (post.attachments > 0) ...[
          const SizedBox(height: 6),
          StatusPill(
            label: '${post.attachments} attachment${post.attachments == 1 ? '' : 's'} on xSiTe',
            tone: Tone.neutral,
            icon: Icons.attach_file,
          ),
        ],
      ],
    );
  }
}
