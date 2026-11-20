import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/lms/domain/calendar.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/event_tile.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/sites/xsite/xsite_service.dart';

/// The student's xSiTe calendar for the next few weeks, by day: due dates,
/// availability and the events instructors add, across their courses (or
/// one [course]'s). Each event opens on xSiTe.
class XsiteCalendarScreen extends StatelessWidget {
  final LmsCourse? course;
  const XsiteCalendarScreen({super.key, this.course});

  @override
  Widget build(BuildContext context) =>
      AuthGate(title: 'xSiTe calendar', builder: (_) => _Agenda(course: course));
}

class _Agenda extends ConsumerStatefulWidget {
  final LmsCourse? course;
  const _Agenda({this.course});

  @override
  ConsumerState<_Agenda> createState() => _AgendaState();
}

class _AgendaState extends ConsumerState<_Agenda> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Loads (or with [refresh], reloads) the calendar, signing in to SIT
  /// again once if the session lapsed. Errors show from the provider.
  Future<void> _load({bool refresh = false}) async {
    if (!mounted) return;
    final p = lmsCalendarProvider;
    if (refresh || ref.read(p).hasError) ref.invalidate(p);
    try {
      await withSignInRetry(ref, () => ref.read(p.future), beforeRetry: () => ref.invalidate(p));
    } catch (_) {
      // Shown from the provider's state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final async = ref.watch(lmsCalendarProvider);
    return AppScaffold(
      appBar: thumbAppBar('xSiTe calendar',
          subtitle: course == null ? 'Next 4 weeks across your courses' : '${course.courseCode} · next 4 weeks'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => openInBrowser(
                    context,
                    course == null
                        ? Uri.parse('${LmsService.base}/d2l/home')
                        : Uri.parse('${LmsService.base}/d2l/le/calendar/${course.orgUnitId}')),
                icon: const Icon(Icons.open_in_new),
                label: Text(course == null ? 'Open xSiTe' : 'Open calendar in xSiTe', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            ThumbIconButton(
                tooltip: 'Refresh', icon: Icons.refresh, onPressed: async.isLoading ? null : () => _load(refresh: true)),
          ],
        ),
      ),
      body: _body(async, course),
    );
  }

  Widget _body(AsyncValue<LmsAgenda> async, LmsCourse? course) {
    final session = ref.watch(sessionControllerProvider);
    final challenge = session.phase == SessionPhase.signingIn ? session.challenge : null;
    if (async.isLoading && challenge != null) {
      return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: MfaCard(challenge: challenge)));
    }
    return switch (async) {
      AsyncValue(hasValue: true, :final value?) => _list(course == null ? value : value.forCourse(course.orgUnitId),
          refreshing: async.isLoading),
      AsyncError(:final error) when error is LmsUnavailableException => const MessageView(
          icon: Icons.event_busy_outlined,
          title: 'Calendar not available',
          message: "xSiTe doesn't share its calendar with the app for your courses.",
        ),
      AsyncError(:final error) => MessageView(
          icon: isSessionError(error) ? Icons.lock_clock : Icons.cloud_off,
          tone: Tone.danger,
          title: "Couldn't load your calendar",
          message: friendlyError(error),
          detail: errorDetail(error),
          action: FilledButton.icon(
              onPressed: () => _load(refresh: true), icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ),
      _ => const MessageView(
          icon: Icons.event_outlined,
          title: 'Loading your calendar…',
          action: SizedBox(width: 160, child: LinearProgressIndicator()),
        ),
    };
  }

  Widget _list(LmsAgenda agenda, {required bool refreshing}) {
    final now = DateTime.now();
    final showCourse = widget.course == null;
    return Column(
      children: [
        RefreshStrip(active: refreshing),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(refresh: true),
            child: agenda.days.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 48),
                      MessageView(
                        icon: Icons.event_available_outlined,
                        title: 'Nothing in the next 4 weeks',
                        message: "xSiTe's calendar has no events for you yet.",
                        compact: true,
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
                    children: [
                      for (final d in agenda.days) ...[
                        Semantics(header: true, child: SectionLabel(agendaDayLabel(d.day, now))),
                        for (final e in d.events) EventTile(event: e, day: d.day, showCourse: showCourse),
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
