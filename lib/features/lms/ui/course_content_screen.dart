import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/ui/course_overview_card.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/features/lms/ui/open_topic.dart';
import 'package:resit/features/lms/ui/topic_tile.dart';

/// A course's content, folder by folder, as on xSiTe, with how much is
/// done and the course overview on top. Done items stay listed (ticked and
/// dimmed) so they can be opened again. Links open at their own address;
/// PDFs, images and text in the app, other documents in a device app, otherwise
/// on xSiTe.
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
    ref.invalidate(lmsOverviewProvider(course.orgUnitId));
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
            CourseOverviewCard(course: course),
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
          onPressed: () => openInBrowser(context, contentHome(course)),
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
          for (final t in m.topics) TopicTile(topic: t, done: isDone(t)),
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
