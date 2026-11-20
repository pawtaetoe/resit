import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/lms/ui/new_badge.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/course_screen.dart';

/// "today", "yesterday", "3 days ago", "2 weeks ago", ...
String _ago(DateTime when, DateTime now) {
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(when)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  return '${days ~/ 30} months ago';
}

/// One course in the list: its picture, code and title, how much of it is
/// done, and when it was last opened. Opens the course.
class CourseCard extends ConsumerWidget {
  final LmsCourse course;
  final bool showProgress;
  const CourseCard({super.key, required this.course, this.showProgress = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final AsyncValue<CourseProgress?> progress =
        showProgress ? ref.watch(lmsProgressProvider(course.orgUnitId)) : const AsyncData(null);
    final p = progress.valueOrNull;
    final seen = course.lastAccessed;
    final updates = ref.watch(lmsUpdatesProvider.select((u) => u.valueOrNull?[course.orgUnitId]));

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
                    Row(
                      children: [
                        Expanded(
                          child: Text(course.courseCode,
                              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                        ),
                        NewBadge.forCourse(updates),
                      ],
                    ),
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
