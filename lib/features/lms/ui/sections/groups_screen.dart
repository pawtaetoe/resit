import 'package:flutter/material.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/sections/section_scaffold.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

class GroupsScreen extends StatelessWidget {
  final LmsCourse course;
  const GroupsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionScaffold<List<MyGroup>>(
      course: course,
      title: 'Groups',
      provider: lmsGroupsProvider(course.orgUnitId),
      xsitePage: courseToolPage('/d2l/lms/group/group_list.d2l', course.orgUnitId),
      icon: Icons.groups_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: "You're not in a group in this course",
      builder: (context, list) => [
        for (final g in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.card),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (g.category.isNotEmpty)
                      Text(g.category, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                    Text(g.name, style: theme.textTheme.titleMedium),
                    if (g.description.isNotEmpty) ...[const SizedBox(height: 4), MoreText(g.description, lines: 2)],
                    const SizedBox(height: 8),
                    if (g.members.isEmpty)
                      Text('${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                    else
                      for (final m in g.members)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.person_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(child: Text(m.name)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
