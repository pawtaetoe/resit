import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/sections/announcements_screen.dart';
import 'package:resit/features/lms/ui/meeting_actions.dart';

/// The newest announcements across this trimester's modules: the latest 5,
/// and the rest under "more". Each course's announcements are read side by
/// side (a few requests at a time) and merge in as they arrive. Hidden when
/// there are none.
class TermAnnouncements extends ConsumerWidget {
  static const shown = 5;
  final List<LmsCourse> courses;
  const TermAnnouncements({super.key, required this.courses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = <(LmsCourse, Announcement)>[];
    var loading = 0;
    for (final c in courses) {
      final a = ref.watch(lmsAnnouncementsProvider(c.orgUnitId));
      if (a.isLoading && !a.hasValue) loading++;
      for (final item in a.valueOrNull ?? const <Announcement>[]) {
        all.add((c, item));
      }
    }
    all.sort((a, b) => (b.$2.date ?? DateTime(0)).compareTo(a.$2.date ?? DateTime(0)));
    if (all.isEmpty && loading == 0) return const SizedBox.shrink();

    final latest = all.take(shown).toList();
    final rest = all.skip(shown).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section - Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(loading > 0
              ? 'Latest announcements · checking ${courses.length - loading} of ${courses.length}'
              : 'Latest announcements'),
          if (latest.isEmpty) const Padding(padding: EdgeInsets.only(bottom: Space.card), child: LinearProgressIndicator()),
          for (final (course, a) in latest) _AnnouncementTile(course: course, announcement: a),
          if (rest.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: Text('${rest.length} more announcement${rest.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleSmall),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [for (final (course, a) in rest) _AnnouncementTile(course: course, announcement: a, flat: true)],
              ),
            ),
        ],
      ),
    );
  }
}

/// One announcement: module, title, date, the start of the text. Tapping
/// opens that module's announcements in full.
class _AnnouncementTile extends StatelessWidget {
  final LmsCourse course;
  final Announcement announcement;

  /// Inside the "more" section: no card of its own.
  final bool flat;
  const _AnnouncementTile({required this.course, required this.announcement, this.flat = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final a = announcement;
    final tile = ListTile(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnnouncementsScreen(course: course))),
      leading: Icon(Icons.campaign_outlined, color: theme.colorScheme.primary),
      title: Text(a.title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [course.courseCode, if (a.date != null) DateFormat('d MMM, HH:mm').format(a.date!)].join(' · '),
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          if (a.body.isNotEmpty)
            Text(a.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          if (a.meetings.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: MeetingActions(a.meetings.first)),
        ],
      ),
    );
    if (flat) return tile;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(clipBehavior: Clip.antiAlias, child: tile),
    );
  }
}
