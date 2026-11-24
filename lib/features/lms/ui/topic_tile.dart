import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/open_topic.dart';

/// One item in a course's content: its kind of file, description and
/// whether it's done. A PDF, image or text file opens in the app, another
/// document in an app on the device (with a spinner while it downloads);
/// anything else in the browser.
class TopicTile extends ConsumerStatefulWidget {
  final ContentTopic topic;
  final bool done;
  const TopicTile({super.key, required this.topic, required this.done});

  @override
  ConsumerState<TopicTile> createState() => _TopicTileState();
}

class _TopicTileState extends ConsumerState<TopicTile> {
  bool _opening = false;

  ContentTopic get topic => widget.topic;

  IconData get _icon => switch (topic.extension) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'mp4' || 'mov' || 'webm' => Icons.play_circle_outline,
        'doc' || 'docx' => Icons.description_outlined,
        'ppt' || 'pptx' => Icons.slideshow_outlined,
        'html' || 'htm' => Icons.web_outlined,
        'txt' || 'md' || 'log' => Icons.article_outlined,
        _ when topic.type == 'ContentService' => Icons.play_circle_outline,
        _ when topic.isLink => Icons.link,
        _ => Icons.insert_drive_file_outlined,
      };

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openTopic(context, ref, topic);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final kind = fileTypeLabel(topic);
    final inApp = ref.watch(opensFilesHereProvider) && isDocument(topic);
    return ListTile(
      leading: Icon(_icon, color: widget.done ? muted : theme.colorScheme.primary),
      title: Text(topic.title, style: widget.done ? TextStyle(color: muted) : null),
      subtitle: kind.isEmpty && topic.description.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind.isNotEmpty) Text(kind, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                if (topic.description.isNotEmpty)
                  Text(topic.description, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
      trailing: _opening
          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : widget.done
              ? Icon(Icons.check_circle, color: theme.colorScheme.primary, semanticLabel: 'Done')
              : Icon(
                  !inApp
                      ? Icons.open_in_new
                      : viewFor('.${topic.extension}') == FileView.otherApp
                          ? Icons.download_outlined
                          : Icons.chevron_right,
                  size: 18,
                  color: muted),
      onTap: _open,
    );
  }
}
