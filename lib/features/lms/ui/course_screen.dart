import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/course_content_screen.dart';
import 'package:resit/features/lms/ui/sections/announcements_screen.dart';
import 'package:resit/features/lms/ui/sections/assignments_screen.dart';
import 'package:resit/features/lms/ui/sections/quizzes_screen.dart';
import 'package:resit/features/lms/ui/sections/grades_screen.dart';
import 'package:resit/features/lms/ui/sections/groups_screen.dart';
import 'package:resit/features/lms/discussions_providers.dart';
import 'package:resit/features/lms/ui/sections/discussions_screen.dart';

/// One course: progress through its content, what's due soon, and its
/// sections (content, announcements, assignments, quizzes, grades, groups,
/// discussions).
/// Opening it starts loading every section at once (a few requests at a
/// time), so each is usually ready by the time it's tapped.
class CourseScreen extends ConsumerWidget {
  final LmsCourse course;
  const CourseScreen({super.key, required this.course});

  Future<void> _refresh(WidgetRef ref) async {
    final id = course.orgUnitId;
    for (final p in [
      lmsProgressProvider(id),
      lmsContentsProvider(id),
      lmsAnnouncementsProvider(id),
      lmsAssignmentsProvider(id),
      lmsQuizzesProvider(id),
      lmsGradesProvider(id),
      lmsGroupsProvider(id),
      lmsDiscussionsProvider(id),
    ]) {
      ref.invalidate(p);
    }
    ref.invalidate(lmsCourseDueProvider((id: id, code: course.courseCode)));
    await ref.read(lmsCourseDueProvider((id: id, code: course.courseCode)).future).catchError((_) => <DueItem>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = course.orgUnitId;
    final now = DateTime.now();
    final progress = ref.watch(lmsProgressProvider(id));
    final due = ref.watch(lmsCourseDueProvider((id: id, code: course.courseCode)));
    final announcements = ref.watch(lmsAnnouncementsProvider(id));
    final assignments = ref.watch(lmsAssignmentsProvider(id));
    final quizzes = ref.watch(lmsQuizzesProvider(id));
    final grades = ref.watch(lmsGradesProvider(id));
    final groups = ref.watch(lmsGroupsProvider(id));
    final discussions = ref.watch(lmsDiscussionsProvider(id));
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    /// A tile's subtitle from its section's state.
    String status<T>(AsyncValue<T> v, String Function(T) ready) => v.when(
          data: ready,
          loading: () => 'Loading…',
          error: (e, _) => e is LmsUnavailableException ? 'Not used in this course' : "Couldn't load",
        );

    final p = progress.valueOrNull;
    return AppScaffold(
      appBar: thumbAppBar(course.courseCode, subtitle: course.title),
      bottomNavigationBar: ThumbBar(
        child: FilledButton.tonalIcon(
          onPressed: () => openInBrowser(context, course.homeUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open course in xSiTe', overflow: TextOverflow.ellipsis),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
          children: [
            const SectionLabel('Due soon'),
            ...switch (due) {
              AsyncData(:final value) when value.isEmpty => [
                  const _Note(icon: Icons.task_alt, text: 'Nothing due in the next two weeks.'),
                ],
              AsyncData(:final value) => [for (final d in value) DueTile(item: d, now: now, showCourse: false)],
              AsyncError(:final error) => [_Note(icon: Icons.cloud_off, text: friendlyError(error))],
              _ => [const _Note(icon: Icons.hourglass_empty, text: 'Checking assignments and quizzes…')],
            },
            const SizedBox(height: Space.section),
            const SectionLabel('In this course'),
            _SectionTile(
              icon: Icons.folder_outlined,
              title: 'Content',
              subtitle: p != null && p.required > 0
                  ? '${p.completed} of ${p.required} items done'
                  : status(progress, (_) => 'Lecture notes, files and links'),
              onTap: () => open(CourseContentScreen(course: course)),
            ),
            _SectionTile(
              icon: Icons.campaign_outlined,
              title: 'Announcements',
              subtitle: status(
                  announcements,
                  (list) => list.isEmpty
                      ? 'None yet'
                      : '${list.length} · latest ${list.first.date == null ? '' : DateFormat('d MMM').format(list.first.date!)}'),
              onTap: () => open(AnnouncementsScreen(course: course)),
            ),
            _SectionTile(
              icon: Icons.assignment_outlined,
              title: 'Assignments',
              subtitle: status(assignments, (list) {
                final open = list.where((a) => !a.submitted && (a.endDate ?? a.deadline)?.isAfter(now) != false).length;
                return list.isEmpty ? 'None' : '${list.length} · $open not submitted yet';
              }),
              onTap: () => open(AssignmentsScreen(course: course)),
            ),
            _SectionTile(
              icon: Icons.quiz_outlined,
              title: 'Quizzes',
              subtitle: status(quizzes, (list) => list.isEmpty ? 'None' : '${list.length} quizzes'),
              onTap: () => open(QuizzesScreen(course: course)),
            ),
            _SectionTile(
              icon: Icons.grade_outlined,
              title: 'Grades',
              subtitle: status(
                  grades,
                  (g) => g.items.isEmpty
                      ? 'None released yet'
                      : '${g.items.length} released${g.finalGrade != null ? ' · final grade out' : ''}'),
              onTap: () => open(GradesScreen(course: course)),
            ),
            _SectionTile(
              icon: Icons.groups_outlined,
              title: 'Groups',
              subtitle: status(groups, (list) => list.isEmpty ? "You're not in a group" : list.map((g) => g.name).join(', ')),
              onTap: () => open(GroupsScreen(course: course)),
            ),
            _SectionTile(
              icon: Icons.forum_outlined,
              title: 'Discussions',
              subtitle: status(discussions, (forums) {
                final topics = forums.fold(0, (n, f) => n + f.topics.length);
                String n(int c, String s) => '$c $s${c == 1 ? '' : 's'}';
                return forums.isEmpty ? 'None' : '${n(topics, 'topic')} in ${n(forums.length, 'forum')}';
              }),
              onTap: () => open(DiscussionsScreen(course: course)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SectionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Icon(icon),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

/// A muted one-line note (e.g. "Nothing due").
class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted))),
        ],
      ),
    );
  }
}
