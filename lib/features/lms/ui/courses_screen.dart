import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/features/lms/ui/course_card.dart';
import 'package:resit/features/lms/ui/term_due_soon.dart';
import 'package:resit/features/lms/ui/term_announcements.dart';
import 'package:resit/features/lms/lms_calendar_providers.dart';
import 'package:resit/features/lms/ui/calendar_entry_tile.dart';

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
      if (refresh) {
        ref.invalidate(lmsProgressProvider);
        ref.invalidate(lmsUpdatesProvider);
        ref.invalidate(lmsCalendarProvider);
      }
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
                TermDueSoon(courses: groups[terms.first]!),
                // The calendar: due dates and events by day, next few weeks.
                const CalendarEntryTile(),
                const SizedBox(height: Space.section - Space.card),
                // Announcements from this trimester's modules, newest first.
                TermAnnouncements(courses: groups[terms.first]!),
                for (final term in terms) ...[
                  SectionLabel(term == terms.first ? '$term · this term' : term),
                  for (final c in groups[term]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.card),
                      // Progress only for this term's courses: older ones are done
                      // with, and checking them all costs a request each.
                      child: CourseCard(course: c, showProgress: term == terms.first),
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
