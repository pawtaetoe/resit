import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

String _dateLabel(DateTime d) => DateFormat('d MMM yyyy, HH:mm').format(d);

class AnnouncementsScreen extends StatelessWidget {
  final LmsCourse course;
  const AnnouncementsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionScaffold<List<Announcement>>(
      course: course,
      title: 'Announcements',
      provider: lmsAnnouncementsProvider(course.orgUnitId),
      xsitePage: courseToolPage('/d2l/lms/news/main.d2l', course.orgUnitId),
      icon: Icons.campaign_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: 'No announcements yet',
      builder: (context, list) => [
        for (final a in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.card),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, style: theme.textTheme.titleMedium),
                    if (a.date != null)
                      Text(_dateLabel(a.date!),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (a.body.isNotEmpty) ...[const SizedBox(height: 8), MoreText(a.body)],
                    if (a.attachments > 0) ...[
                      const SizedBox(height: 8),
                      StatusPill(
                        label: '${a.attachments} attachment${a.attachments == 1 ? '' : 's'} on xSiTe',
                        tone: Tone.neutral,
                        icon: Icons.attach_file,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
