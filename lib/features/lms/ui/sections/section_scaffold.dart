import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/xsite/xsite_service.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// xSiTe's own page for one of a course's tools.
Uri courseToolPage(String path, String orgUnitId) => Uri.parse('${LmsService.base}$path?ou=$orgUnitId');

/// The frame every section screen shares: title, loading/error/empty
/// states, pull to refresh, and "Open in xSiTe" in the bottom bar.
class SectionScaffold<T> extends ConsumerWidget {
  final LmsCourse course;
  final String title;
  final FutureProvider<T> provider;
  final Uri xsitePage;
  final IconData icon;
  final bool Function(T) isEmpty;
  final String emptyText;
  final List<Widget> Function(BuildContext, T) build_;
  final Widget? barExtra;

  const SectionScaffold({
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
