import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// Opens a meeting in its app or the browser. Only a link that is still a
/// meeting link on the service's own https host is opened.
Future<void> joinMeeting(BuildContext context, MeetingLink link) async {
  if (meetingServiceOf(link.url) == null) return;
  await openInBrowser(context, link.url);
}

Future<void> _copy(BuildContext context, String what, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) showSuccess(context, '$what copied');
}

/// "Join Zoom" (or Teams, Meet, Webex) for a meeting found in an
/// announcement, with its meeting ID and passcode a tap away from the
/// clipboard when the announcement gives them.
class MeetingActions extends StatelessWidget {
  final MeetingLink link;
  const MeetingActions(this.link, {super.key});

  @override
  Widget build(BuildContext context) {
    final id = link.meetingId, passcode = link.passcode;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => joinMeeting(context, link),
          icon: const Icon(Icons.videocam_outlined),
          label: Text('Join ${link.service.label}'),
        ),
        if (id != null)
          ActionChip(
            avatar: const Icon(Icons.copy, size: 16),
            label: Text('ID $id'),
            tooltip: 'Copy meeting ID',
            onPressed: () => _copy(context, 'Meeting ID', id.replaceAll(' ', '')),
          ),
        if (passcode != null)
          ActionChip(
            avatar: const Icon(Icons.copy, size: 16),
            label: const Text('Passcode'),
            tooltip: 'Copy passcode',
            onPressed: () => _copy(context, 'Passcode', passcode),
          ),
      ],
    );
  }
}

/// A compact "Join" for a class row. A long press shows the meeting's ID
/// and passcode to copy.
class MeetingJoinButton extends StatelessWidget {
  final MeetingLink link;

  /// e.g. "INF 2004 Lecture", for the long-press sheet.
  final String title;
  const MeetingJoinButton(this.link, {super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: 'Joins on ${link.service.label}',
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: () => joinMeeting(context, link),
        onLongPress: link.meetingId == null && link.passcode == null ? null : () => _details(context),
        icon: const Icon(Icons.videocam_outlined, size: 18),
        label: const Text('Join'),
      ),
    );
  }

  void _details(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$title on ${link.service.label}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                MeetingActions(link),
              ],
            ),
          ),
        ),
      );
}
