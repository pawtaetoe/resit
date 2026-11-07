import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/data/lms_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser (xSiTe pages need its full web app).
Future<void> openInBrowser(BuildContext context, Uri url) async {
  final ok = await launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) showError(context, "Couldn't open the browser.");
}

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
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
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
    Future<List<LmsCourse>> fetch() => service.courses(onMfaChallenge: (c) {
          if (mounted) setState(() => _challenge = c);
        });
    try {
      List<LmsCourse> courses;
      try {
        courses = await fetch();
      } on SessionExpiredException {
        // Sign in to SIT afresh automatically, then try once more.
        final ok = await ref.read(sessionControllerProvider.notifier).ensureSignedIn(force: true);
        if (!ok) rethrow;
        courses = await fetch();
      }
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
    return Scaffold(
      appBar: thumbAppBar('Courses', subtitle: const Text('From xSiTe', style: TextStyle(fontSize: 13))),
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
            SizedBox.square(
              dimension: ThumbBar.heightOf(context),
              child: IconButton.outlined(
                tooltip: 'Refresh',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ),
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
      if (!ref.watch(authStateProvider) && !_loading) {
        return MessageView(
          icon: Icons.lock_outline,
          title: 'Sign in to see your courses',
          message: 'xSiTe uses your SIT account.',
          action: FilledButton(
            onPressed: () {
              ref.read(homeTabProvider.notifier).state = AppTab.account;
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: const Text('Go to sign in'),
          ),
        );
      }
      return const MessageView(
        icon: Icons.school_outlined,
        title: 'Opening xSiTe…',
        message: 'Signing in with your SIT account.',
        action: SizedBox(width: 160, child: LinearProgressIndicator()),
      );
    }
    if (courses.isEmpty) {
      return const MessageView(icon: Icons.school_outlined, title: 'No courses', message: "xSiTe didn't list any.");
    }

    // Grouped by term, newest first (the list is already in that order).
    final groups = <String, List<LmsCourse>>{};
    for (final c in courses) {
      groups.putIfAbsent(c.termLabel, () => []).add(c);
    }
    final terms = groups.keys.toList();

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_loading) const LinearProgressIndicator(),
          for (final term in terms) ...[
            SectionLabel(term == terms.first ? '$term · this term' : term),
            for (final c in groups[term]!)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: _CourseCard(course: c)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  final LmsCourse course;
  const _CourseCard({required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final progress = ref.watch(lmsProgressProvider(course.orgUnitId));
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
                    Text(course.courseCode, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
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
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Text(
        course.courseCode.replaceAll(RegExp(r'\d'), ''),
        style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.bold),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: FutureBuilder<Uint8List?>(
          future: ref.read(lmsServiceProvider).image(course),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) return placeholder;
            return Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
          },
        ),
      ),
    );
  }
}

/// One course: how much is done, then its content folder by folder, as on
/// xSiTe. "To do" (the default) hides what's already done. Items open in the
/// browser: links at their own address, files on xSiTe.
class CourseScreen extends ConsumerStatefulWidget {
  final LmsCourse course;
  const CourseScreen({super.key, required this.course});

  @override
  ConsumerState<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends ConsumerState<CourseScreen> {
  bool _todoOnly = true;

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
    final theme = Theme.of(context);
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
              action: FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      final shown = [
        for (final m in modules)
          if (!_todoOnly || m.allTopics.any((t) => !isDone(t))) m,
      ];
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (p != null) _ProgressCard(course: course, progress: p),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              MessageView(
                icon: Icons.task_alt,
                tone: Tone.success,
                title: _todoOnly ? 'All caught up' : 'No content yet',
                message: _todoOnly ? "You've opened everything in this course." : null,
              ),
            for (final m in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ModuleCard(module: m, isDone: isDone, todoOnly: _todoOnly),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: thumbAppBar(course.courseCode, subtitle: Text(course.title, style: const TextStyle(fontSize: 13))),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ThumbToggle<bool>(
                options: const [
                  ThumbToggleOption(true, 'To do', icon: Icons.radio_button_unchecked),
                  ThumbToggleOption(false, 'All', icon: Icons.list),
                ],
                selected: _todoOnly,
                onChanged: (v) => setState(() => _todoOnly = v),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: ThumbBar.heightOf(context),
              child: IconButton.outlined(
                tooltip: 'Open course in xSiTe',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => openInBrowser(context, course.homeUrl),
                icon: Icon(Icons.open_in_new, color: theme.colorScheme.primary),
              ),
            ),
          ],
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
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            Text('${p.completed} of ${p.required} items · ${course.termLabel}', style: TextStyle(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// A top-level folder: its name, how much of it is done, and its items,
/// with sub-folders as headings. Starts open if anything in it is left to do.
class _ModuleCard extends StatelessWidget {
  final ContentModule module;
  final bool Function(ContentTopic) isDone;
  final bool todoOnly;
  const _ModuleCard({required this.module, required this.isDone, required this.todoOnly});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = module.allTopics.toList();
    final done = all.where(isDone).length;

    List<Widget> rows(ContentModule m, int depth) => [
          for (final t in m.topics)
            if (!todoOnly || !isDone(t)) _TopicTile(topic: t, done: isDone(t)),
          for (final sub in m.modules)
            if (!todoOnly || sub.allTopics.any((t) => !isDone(t))) ...[
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
      child: Theme(
        // No divider lines around the expanding section.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: done < all.length,
          title: Text(module.title, style: theme.textTheme.titleMedium),
          subtitle: Text('$done of ${all.length} done',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: rows(module, 0),
        ),
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
      subtitle: topic.description.isEmpty
          ? null
          : Text(topic.description, maxLines: 3, overflow: TextOverflow.ellipsis),
      trailing: done
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary, semanticLabel: 'Done')
          : Icon(Icons.open_in_new, size: 18, color: muted),
      onTap: () => openInBrowser(context, topic.openUrl),
    );
  }
}
