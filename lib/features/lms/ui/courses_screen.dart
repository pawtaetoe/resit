import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/course_screen.dart';
import 'package:resit/features/lms/ui/due_tile.dart';
import 'package:resit/features/lms/ui/sections/announcements_screen.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/core/widgets/desktop.dart';

/// "today", "yesterday", "3 days ago", "2 weeks ago", ...
String _ago(DateTime when, DateTime now) {
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(when)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  return '${days ~/ 30} months ago';
}

/// Courses on xSiTe (SIT's LMS): this term's first, each with how much of
/// its content is done. A course opens its to-do list.
class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) => AuthGate(title: 'xSiTe courses', builder: (_) => const _Courses());
}

class _Courses extends ConsumerStatefulWidget {
  const _Courses();

  @override
  ConsumerState<_Courses> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<_Courses> {
  List<LmsCourse>? _courses;
  Object? _error;
  bool _loading = false;
  MfaChallenge? _challenge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final service = ref.read(lmsServiceProvider);
    Future<List<LmsCourse>> fetch() => service.courses(
        force: refresh,
        onMfaChallenge: (c) {
          if (mounted) setState(() => _challenge = c);
        });
    try {
      final courses = await withSignInRetry(ref, fetch);
      if (refresh) ref.invalidate(lmsProgressProvider);
      if (mounted) setState(() => _courses = courses);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _challenge = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: thumbAppBar('xSiTe courses', subtitle: 'Progress and what to do next'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => openInBrowser(context, Uri.parse('${LmsService.base}/d2l/home')),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open xSiTe'),
              ),
            ),
            const SizedBox(width: 8),
            ThumbIconButton(
                tooltip: 'Refresh', icon: Icons.refresh, onPressed: _loading ? null : () => _load(refresh: true)),
          ],
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final session = ref.watch(sessionControllerProvider);
    final challenge = _challenge ?? (session.phase == SessionPhase.signingIn ? session.challenge : null);
    final courses = _courses;

    if (_loading && challenge != null) {
      return Center(
          child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: MfaCard(challenge: challenge)));
    }
    if (courses == null) {
      if (_error != null) {
        return MessageView(
          icon: isSessionError(_error!) ? Icons.lock_clock : Icons.cloud_off,
          tone: Tone.danger,
          title: "Couldn't load your courses",
          message: friendlyError(_error!),
          detail: errorDetail(_error!),
          action: FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        );
      }
      return const MessageView(
        icon: Icons.menu_book_outlined,
        title: 'Opening xSiTe…',
        message: 'Signing in with your SIT account.',
        action: SizedBox(width: 160, child: LinearProgressIndicator()),
      );
    }
    if (courses.isEmpty) {
      return const MessageView(icon: Icons.menu_book_outlined, title: 'No courses', message: "xSiTe didn't list any.");
    }

    // Grouped by term, newest first (the list is already in that order).
    final groups = <String, List<LmsCourse>>{};
    for (final c in courses) {
      groups.putIfAbsent(c.termLabel, () => []).add(c);
    }
    final terms = groups.keys.toList();

    return Column(
      children: [
        RefreshStrip(active: _loading),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(refresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
              children: [
                // Deadlines across this term's courses, soonest first.
                _TermDueSoon(courses: groups[terms.first]!),
                // Announcements from this trimester's modules, newest first.
                TermAnnouncements(courses: groups[terms.first]!),
                for (final term in terms) ...[
                  SectionLabel(term == terms.first ? '$term · this term' : term),
                  for (final c in groups[term]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.card),
                      // Progress only for this term's courses: older ones are done
                      // with, and checking them all costs a request each.
                      child: _CourseCard(course: c, showProgress: term == terms.first),
                    ),
                  const SizedBox(height: Space.section - Space.card),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CourseCard extends ConsumerWidget {
  final LmsCourse course;
  final bool showProgress;
  const _CourseCard({required this.course, this.showProgress = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final AsyncValue<CourseProgress?> progress =
        showProgress ? ref.watch(lmsProgressProvider(course.orgUnitId)) : const AsyncData(null);
    final p = progress.valueOrNull;
    final seen = course.lastAccessed;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: course.canAccess
            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => CourseScreen(course: course)))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CourseImage(course: course, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.courseCode,
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                    Text(course.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    if (p != null && p.required > 0) ...[
                      LinearProgressIndicator(value: p.fraction, borderRadius: BorderRadius.circular(4)),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      [
                        if (p != null && p.required > 0) '${p.completed} of ${p.required} items done',
                        if (progress.isLoading) 'Checking progress…',
                        if (seen != null) 'opened ${_ago(seen, DateTime.now())}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The course's picture from xSiTe, or its code's initials while it loads or
/// if it has none.
class _CourseImage extends ConsumerWidget {
  final LmsCourse course;
  final double size;
  const _CourseImage({required this.course, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        course.courseCode.replaceAll(RegExp(r'\d'), ''),
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
      ),
    );
    // Decoded at the size it's shown, not the size it was sent.
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: size,
        child: FutureBuilder<Uint8List?>(
          future: ref.read(lmsServiceProvider).image(course),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) return placeholder;
            return Image.memory(bytes,
                fit: BoxFit.cover, cacheWidth: cacheSize, errorBuilder: (_, __, ___) => placeholder);
          },
        ),
      ),
    );
  }
}

/// A course's content, folder by folder, as on xSiTe, with how much is done. Done items stay listed (ticked and dimmed) so they can be opened
/// again. Items open in the browser: links at their own address, files on
/// xSiTe.
class CourseContentScreen extends ConsumerStatefulWidget {
  final LmsCourse course;
  const CourseContentScreen({super.key, required this.course});

  @override
  ConsumerState<CourseContentScreen> createState() => _CourseContentScreenState();
}

class _CourseContentScreenState extends ConsumerState<CourseContentScreen> {
  LmsCourse get course => widget.course;

  Future<void> _refresh() async {
    ref.invalidate(lmsProgressProvider(course.orgUnitId));
    ref.invalidate(lmsContentsProvider(course.orgUnitId));
    await Future.wait([
      ref.read(lmsProgressProvider(course.orgUnitId).future),
      ref.read(lmsContentsProvider(course.orgUnitId).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final progressAsync = ref.watch(lmsProgressProvider(course.orgUnitId));
    final contentsAsync = ref.watch(lmsContentsProvider(course.orgUnitId));
    final p = progressAsync.valueOrNull;
    final modules = contentsAsync.valueOrNull;

    // Done per item, from xSiTe's completion counts; an item it doesn't count
    // is done once it has been opened.
    final doneById = {for (final i in p?.items ?? const <ContentItem>[]) i.objectId: i.done};
    bool isDone(ContentTopic t) => doneById[t.id] ?? !t.unread;

    final error = contentsAsync.error ?? progressAsync.error;
    final Widget body;
    if (modules == null) {
      body = error != null
          ? MessageView(
              icon: Icons.cloud_off,
              tone: Tone.danger,
              title: "Couldn't load this course",
              message: friendlyError(error),
              action: FilledButton.icon(
                  onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            )
          : const MessageView(
              icon: Icons.menu_book_outlined,
              title: 'Opening the course…',
              action: SizedBox(width: 160, child: LinearProgressIndicator()),
            );
    } else {
      // Everything stays listed: done items are ticked, not removed, so
      // something already read is still there to open again.
      final shown = modules;
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
          children: [
            if (p != null) _ProgressCard(course: course, progress: p),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const MessageView(
                icon: Icons.task_alt,
                tone: Tone.success,
                title: 'No content yet',
              ),
            for (final m in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ModuleCard(module: m, isDone: isDone),
              ),
          ],
        ),
      );
    }

    return AppScaffold(
      appBar: thumbAppBar('Content', subtitle: '${course.courseCode} · ${course.title}'),
      bottomNavigationBar: ThumbBar(
        child: FilledButton.tonalIcon(
          onPressed: () => openInBrowser(context, Uri.parse('${LmsService.base}/d2l/le/content/${course.orgUnitId}/Home')),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open in xSiTe', overflow: TextOverflow.ellipsis),
        ),
      ),
      body: body,
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final LmsCourse course;
  final CourseProgress progress;
  const _ProgressCard({required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onPrimaryContainer;
    final p = progress;
    return TintedCard(
      color: theme.colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.required == 0 ? 'Nothing to track' : '${(p.fraction * 100).round()}% done',
            style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: p.fraction, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 6),
          Text('${p.completed} of ${p.required} items · ${course.termLabel}',
              style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// A top-level folder: its name, how much of it is done, and its items,
/// with sub-folders as headings. Starts open if anything in it is left to do;
/// a finished folder starts closed but is still there to open.
class _ModuleCard extends StatelessWidget {
  final ContentModule module;
  final bool Function(ContentTopic) isDone;
  const _ModuleCard({required this.module, required this.isDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = module.allTopics.toList();
    final done = all.where(isDone).length;

    List<Widget> rows(ContentModule m, int depth) => [
          for (final t in m.topics) _TopicTile(topic: t, done: isDone(t)),
          for (final sub in m.modules) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(16.0 + depth * 12, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(sub.title, style: theme.textTheme.labelLarge)),
                ],
              ),
            ),
            ...rows(sub, depth + 1),
          ],
        ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: done < all.length,
        title: Text(module.title, style: theme.textTheme.titleMedium),
        subtitle: Text('$done of ${all.length} done',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: rows(module, 0),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  final ContentTopic topic;
  final bool done;
  const _TopicTile({required this.topic, required this.done});

  IconData get _icon => switch (topic.extension) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'mp4' || 'mov' || 'webm' => Icons.play_circle_outline,
        'doc' || 'docx' => Icons.description_outlined,
        'ppt' || 'pptx' => Icons.slideshow_outlined,
        'html' || 'htm' => Icons.web_outlined,
        _ when topic.type == 'ContentService' => Icons.play_circle_outline,
        _ when topic.isLink => Icons.link,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      leading: Icon(_icon, color: done ? muted : theme.colorScheme.primary),
      title: Text(topic.title, style: done ? TextStyle(color: muted) : null),
      subtitle:
          topic.description.isEmpty ? null : Text(topic.description, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: done
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary, semanticLabel: 'Done')
          : Icon(Icons.open_in_new, size: 18, color: muted),
      onTap: () => openInBrowser(context, topic.openUrl),
    );
  }
}

/// "Due soon" across this term's courses: each course's assignments and
/// quizzes are read side by side (a few requests at a time), and deadlines
/// show as they arrive. Hidden when nothing is due.
class _TermDueSoon extends ConsumerWidget {
  final List<LmsCourse> courses;
  const _TermDueSoon({required this.courses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final items = <DueItem>[];
    var loading = 0;
    for (final c in courses) {
      final due = ref.watch(lmsCourseDueProvider((id: c.orgUnitId, code: c.courseCode)));
      if (due.isLoading && !due.hasValue) loading++;
      items.addAll(due.valueOrNull ?? const []);
    }
    items.sort((a, b) => a.due.compareTo(b.due));
    if (items.isEmpty && loading == 0) return const SizedBox.shrink();
    final shown = items.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section - Space.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(loading > 0 ? 'Due soon · checking ${courses.length - loading} of ${courses.length}' : 'Due soon'),
          for (final d in shown) DueTile(item: d, now: now),
          if (items.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: Space.card),
              child: Text('+${items.length - shown.length} more in the courses below',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          if (shown.isEmpty) const Padding(padding: EdgeInsets.only(bottom: Space.card), child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}

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
