import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/data/lms_activities.dart';
import 'package:resit/features/lms/data/lms_service.dart';
import 'package:resit/features/lms/presentation/courses_screen.dart';
import 'package:resit/core/widgets/desktop.dart';

/// xSiTe's own page for one of a course's tools.
Uri _toolPage(String path, String orgUnitId) => Uri.parse('${LmsService.base}$path?ou=$orgUnitId');

/// "Today, 23:59", "Tomorrow, 14:00", "Fri 21 Nov, 23:59"; "Was due …" once past.
String dueLabel(DateTime due, DateTime now) {
  final day = DateUtils.isSameDay(due, now)
      ? 'Today'
      : DateUtils.isSameDay(due, now.add(const Duration(days: 1)))
          ? 'Tomorrow'
          : DateFormat(due.year == now.year ? 'EEE d MMM' : 'EEE d MMM yyyy').format(due);
  final at = '$day, ${DateFormat('HH:mm').format(due)}';
  return due.isBefore(now) ? 'Was due $at' : 'Due $at';
}

/// How urgent a deadline is: past (danger), within a day (warning), later.
Tone dueTone(DateTime due, DateTime now) => due.isBefore(now)
    ? Tone.danger
    : due.difference(now) < const Duration(days: 1)
        ? Tone.warning
        : Tone.neutral;

String _dateLabel(DateTime d) => DateFormat('d MMM yyyy, HH:mm').format(d);

/// One course: progress through its content, what's due soon, and its
/// sections (content, announcements, assignments, quizzes, grades, groups).
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

/// One deadline: what, which course, when (coloured by urgency). Opens on
/// xSiTe.
class DueTile extends StatelessWidget {
  final DueItem item;
  final DateTime now;
  final bool showCourse;
  const DueTile({super.key, required this.item, required this.now, this.showCourse = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = dueTone(item.due, now);
    final (bg, fg) = tone.colors(theme.colorScheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => openInBrowser(context, item.url),
          leading: CircleAvatar(
            backgroundColor: bg,
            foregroundColor: fg,
            child: Icon(item.isQuiz ? Icons.quiz_outlined : Icons.assignment_outlined),
          ),
          title: Text(showCourse ? '${item.courseCode} · ${item.title}' : item.title,
              style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(dueLabel(item.due, now),
              style: tone == Tone.neutral ? null : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.open_in_new, size: 18),
        ),
      ),
    );
  }
}

/// The frame every section screen shares: title, loading/error/empty
/// states, pull to refresh, and "Open in xSiTe" in the bottom bar.
class _SectionScaffold<T> extends ConsumerWidget {
  final LmsCourse course;
  final String title;
  final FutureProvider<T> provider;
  final Uri xsitePage;
  final IconData icon;
  final bool Function(T) isEmpty;
  final String emptyText;
  final List<Widget> Function(BuildContext, T) build_;
  final Widget? barExtra;

  const _SectionScaffold({
    super.key,
    required this.course,
    required this.title,
    required this.provider,
    required this.xsitePage,
    required this.icon,
    required this.isEmpty,
    required this.emptyText,
    required List<Widget> Function(BuildContext, T) builder,
    this.barExtra,
  }) : build_ = builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    Future<void> refresh() async {
      ref.invalidate(provider);
      await ref.read(provider.future).then((_) {}).catchError((_) {});
    }

    final Widget body = switch (async) {
      AsyncValue(hasValue: true, :final value) when isEmpty(value as T) => MessageView(icon: icon, title: emptyText),
      AsyncValue(hasValue: true, :final value) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
            children: build_(context, value as T),
          ),
        ),
      AsyncError(:final error) => MessageView(
          icon: error is LmsUnavailableException ? icon : Icons.cloud_off,
          tone: error is LmsUnavailableException ? Tone.neutral : Tone.danger,
          title: error is LmsUnavailableException ? 'Not used in this course' : "Couldn't load ${title.toLowerCase()}",
          message: error is LmsUnavailableException ? 'xSiTe has no ${title.toLowerCase()} here for you.' : friendlyError(error),
          detail: error is LmsUnavailableException ? null : errorDetail(error),
          action: error is LmsUnavailableException
              ? null
              : FilledButton.icon(onPressed: refresh, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ),
      _ => MessageView(
          icon: icon,
          title: 'Loading ${title.toLowerCase()}…',
          action: const SizedBox(width: 160, child: LinearProgressIndicator()),
        ),
    };

    return AppScaffold(
      appBar: thumbAppBar(title, subtitle: '${course.courseCode} · ${course.title}'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => openInBrowser(context, xsitePage),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in xSiTe', overflow: TextOverflow.ellipsis),
              ),
            ),
            if (barExtra != null) ...[const SizedBox(width: 8), barExtra!],
          ],
        ),
      ),
      body: body,
    );
  }
}

/// Text that shows a few lines and expands on tap.
class _MoreText extends StatefulWidget {
  final String text;
  final int lines;
  const _MoreText(this.text, {this.lines = 4});

  @override
  State<_MoreText> createState() => _MoreTextState();
}

class _MoreTextState extends State<_MoreText> {
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

// ---------------------------------------------------------------------------

class AnnouncementsScreen extends StatelessWidget {
  final LmsCourse course;
  const AnnouncementsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionScaffold<List<Announcement>>(
      course: course,
      title: 'Announcements',
      provider: lmsAnnouncementsProvider(course.orgUnitId),
      xsitePage: _toolPage('/d2l/lms/news/main.d2l', course.orgUnitId),
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
                    if (a.body.isNotEmpty) ...[const SizedBox(height: 8), _MoreText(a.body)],
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

class AssignmentsScreen extends ConsumerWidget {
  final LmsCourse course;
  const AssignmentsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final grades = ref.watch(lmsGradesProvider(course.orgUnitId)).valueOrNull;
    final visible = ref.watch(gradesVisibleProvider);
    return _SectionScaffold<List<Assignment>>(
      course: course,
      title: 'Assignments',
      provider: lmsAssignmentsProvider(course.orgUnitId),
      xsitePage: _toolPage('/d2l/lms/dropbox/dropbox.d2l', course.orgUnitId),
      icon: Icons.assignment_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: 'No assignments',
      barExtra: const GradeVisibilityButton(inBar: true),
      builder: (context, list) => [
        for (final a in list)
          Builder(builder: (context) {
            final score = grades?.forItem(a.gradeItemId);
            final deadline = a.deadline;
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.card),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openInBrowser(context, a.url),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(a.name, style: theme.textTheme.titleMedium)),
                            Icon(Icons.open_in_new, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (a.submitted)
                              StatusPill(
                                label: 'Submitted ${DateFormat('d MMM, HH:mm').format(a.lastSubmitted!)}',
                                tone: Tone.success,
                                icon: Icons.check,
                              )
                            else if (deadline != null)
                              StatusPill(
                                label: dueLabel(deadline, now),
                                tone: dueTone(deadline, now) == Tone.neutral ? Tone.info : dueTone(deadline, now),
                                icon: Icons.schedule,
                              ),
                            if (a.submitted && deadline != null)
                              StatusPill(label: dueLabel(deadline, now), tone: Tone.neutral, icon: Icons.schedule),
                            if (a.isGroup) const StatusPill(label: 'Group', tone: Tone.neutral, icon: Icons.groups_outlined),
                            if (score != null)
                              StatusPill(
                                label: 'Grade: ${visible ? score.summary : hiddenValue}',
                                tone: Tone.info,
                                icon: Icons.grade_outlined,
                              ),
                          ],
                        ),
                        if (a.instructions.isNotEmpty) ...[const SizedBox(height: 8), _MoreText(a.instructions, lines: 3)],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class QuizzesScreen extends ConsumerWidget {
  final LmsCourse course;
  const QuizzesScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final grades = ref.watch(lmsGradesProvider(course.orgUnitId)).valueOrNull;
    final visible = ref.watch(gradesVisibleProvider);
    return _SectionScaffold<List<Quiz>>(
      course: course,
      title: 'Quizzes',
      provider: lmsQuizzesProvider(course.orgUnitId),
      xsitePage: _toolPage('/d2l/lms/quizzing/quizzing.d2l', course.orgUnitId),
      icon: Icons.quiz_outlined,
      isEmpty: (l) => l.isEmpty,
      emptyText: 'No quizzes',
      barExtra: const GradeVisibilityButton(inBar: true),
      builder: (context, list) => [
        for (final q in list)
          Builder(builder: (context) {
            final score = grades?.forItem(q.gradeItemId);
            final deadline = q.deadline;
            final opens = q.startDate != null && q.startDate!.isAfter(now) ? q.startDate : null;
            final closed = q.endDate != null && q.endDate!.isBefore(now);
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.card),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => openInBrowser(context, q.url),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(q.name, style: theme.textTheme.titleMedium)),
                            Icon(Icons.open_in_new, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (score != null)
                              StatusPill(
                                label: 'Score: ${visible ? score.summary : hiddenValue}',
                                tone: Tone.success,
                                icon: Icons.grade_outlined,
                              ),
                            if (opens != null)
                              StatusPill(label: 'Opens ${DateFormat('EEE d MMM, HH:mm').format(opens)}', tone: Tone.neutral)
                            else if (closed)
                              const StatusPill(label: 'Closed', tone: Tone.neutral)
                            else if (deadline != null)
                              StatusPill(
                                label: dueLabel(deadline, now),
                                tone: dueTone(deadline, now) == Tone.neutral ? Tone.info : dueTone(deadline, now),
                                icon: Icons.schedule,
                              ),
                            StatusPill(
                              label: q.attemptsAllowed == null
                                  ? 'Unlimited attempts'
                                  : '${q.attemptsAllowed} attempt${q.attemptsAllowed == 1 ? '' : 's'}',
                              tone: Tone.neutral,
                            ),
                            if (q.timeLimit != null)
                              StatusPill(label: '${q.timeLimit} min', tone: Tone.neutral, icon: Icons.timer_outlined),
                          ],
                        ),
                        if (q.description.isNotEmpty) ...[const SizedBox(height: 8), _MoreText(q.description, lines: 3)],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class GradesScreen extends ConsumerWidget {
  final LmsCourse course;
  const GradesScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final visible = ref.watch(gradesVisibleProvider);
    String v(String s) => visible ? s : hiddenValue;
    return _SectionScaffold<CourseGrades>(
      course: course,
      title: 'Grades',
      provider: lmsGradesProvider(course.orgUnitId),
      xsitePage: _toolPage('/d2l/lms/grades/index.d2l', course.orgUnitId),
      icon: Icons.grade_outlined,
      isEmpty: (g) => g.items.isEmpty && g.finalGrade == null,
      emptyText: 'No grades released yet',
      barExtra: const GradeVisibilityButton(inBar: true),
      builder: (context, g) => [
        if (g.finalGrade case final f?) ...[
          StatTile(
            tinted: true,
            value: v(f.summary),
            caption: 'final grade',
            semanticsLabel: visible ? null : 'Final grade, hidden',
          ),
          const SizedBox(height: Space.section),
        ],
        for (final e in g.items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.card),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.inset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.name, style: theme.textTheme.titleSmall),
                              if (e.type.isNotEmpty)
                                Text(e.type,
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: visible ? null : '${e.name}, hidden',
                          excludeSemantics: !visible,
                          child: Text(v(e.summary),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    if (visible && e.weighted != null && e.weightedOutOf != null && e.weightedOutOf! > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Counts ${e.weighted!.toStringAsFixed(1)} of ${e.weightedOutOf!.toStringAsFixed(1)} towards the course',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    if (visible && e.comment.isNotEmpty) ...[const SizedBox(height: 8), _MoreText(e.comment, lines: 3)],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class GroupsScreen extends StatelessWidget {
  final LmsCourse course;
  const GroupsScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionScaffold<List<MyGroup>>(
      course: course,
      title: 'Groups',
      provider: lmsGroupsProvider(course.orgUnitId),
      xsitePage: _toolPage('/d2l/lms/group/group_list.d2l', course.orgUnitId),
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
                    if (g.description.isNotEmpty) ...[const SizedBox(height: 4), _MoreText(g.description, lines: 2)],
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
