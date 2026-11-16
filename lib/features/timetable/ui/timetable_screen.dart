import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/timetable/ui/course_palette.dart';
import 'package:resit/features/timetable/ui/timetable_view_model.dart';
import 'package:resit/features/timetable/ui/week_grid.dart';
import 'package:resit/features/timetable/ui/week_grid_layout.dart';

/// The weekly class timetable from in4SIT. Opens at the week of
/// [initialDate] (this week by default). Signs in first if needed.
class TimetableScreen extends StatelessWidget {
  final DateTime? initialDate;
  const TimetableScreen({super.key, this.initialDate});

  @override
  Widget build(BuildContext context) => AuthGate(
        title: 'Timetable',
        builder: (_) => _Timetable(initialDate: initialDate),
        // While signing in, or when SIT can't be reached, the saved weeks
        // are shown instead of a wait or an error.
        offlineBuilder: (_, session) => _Timetable(initialDate: initialDate, offline: session),
      );
}

/// Gives each timetable screen its own [TimetableViewModel]: kept while the
/// screen shows (signed in or offline), dropped with it.
class _Timetable extends StatelessWidget {
  final DateTime? initialDate;
  final SessionState? offline;

  const _Timetable({this.initialDate, this.offline});

  @override
  Widget build(BuildContext context) => ProviderScope(
        overrides: [timetableViewModelProvider.overrideWith(TimetableViewModel.new)],
        child: _TimetableView(initialDate: initialDate, offline: offline),
      );
}

class _TimetableView extends ConsumerStatefulWidget {
  final DateTime? initialDate;

  /// Set while not signed in (signing in, or sign-in failed): only saved
  /// weeks are shown and nothing is fetched.
  final SessionState? offline;

  const _TimetableView({this.initialDate, this.offline});

  @override
  ConsumerState<_TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends ConsumerState<_TimetableView> {
  // The week pager is "infinite": page 1000 is the current week.
  static const _initialPage = 1000;

  late final PageController _pageController;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = _initialPage;
    if (widget.initialDate case final date?) {
      final now = DateTime.now();
      final thisMonday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final monday = DateTime(date.year, date.month, date.day - (date.weekday - 1));
      _page = _initialPage + (monday.difference(thisMonday).inHours / (24 * 7)).round();
    }
    _pageController = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _weekStart(int page) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day + (page - _initialPage) * 7);
  }

  String _weekLabel(DateTime monday) {
    final friday = DateTime(monday.year, monday.month, monday.day + WeekGridLayout.dayCount - 1);
    final sameYear = monday.year == friday.year;
    final start = DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(monday);
    final end = DateFormat('d MMM yyyy').format(friday);
    return '$start - $end';
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildWeekPage(int page) {
    final monday = _weekStart(page);
    final timetable = ref.watch(timetableViewModelProvider);
    final viewModel = ref.read(timetableViewModelProvider.notifier);
    final TimetableWeek(:live, :saved, :error, :loading, schedule: week) = timetable.weekOf(monday);
    final offline = widget.offline;

    if (offline == null && live == null && error == null && !loading) {
      // Not requested yet: fetch it once this page is built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.offline == null) viewModel.loadWeek(monday);
      });
    }

    // MFA from in4SIT's own sign-in, or from the automatic sign-in retry.
    final sessionState = ref.watch(sessionControllerProvider);
    final challenge =
        timetable.mfaChallenge ?? (sessionState.phase == SessionPhase.signingIn ? sessionState.challenge : null);
    if (challenge != null && loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MfaCard(challenge: challenge),
        ),
      );
    }

    if (week == null && offline != null) {
      final failed = offline.phase == SessionPhase.failed;
      return MessageView(
        icon: failed ? Icons.cloud_off : Icons.sync,
        tone: failed ? Tone.danger : Tone.neutral,
        title: failed ? "Couldn't reach SIT" : 'Signing in to SIT…',
        message: failed
            ? 'There is no saved copy of this week yet. Weeks you have opened are kept for when SIT is down.'
            : 'This week will appear once you are signed in.',
        action: failed ? _signInAgainButton() : const SizedBox(width: 160, child: LinearProgressIndicator()),
      );
    }

    if (week == null && error != null) {
      final session = isSessionError(error);
      final retry = FilledButton.icon(
        onPressed: () => viewModel.refresh(monday),
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      );
      return MessageView(
        icon: session ? Icons.lock_clock : Icons.cloud_off,
        tone: Tone.danger,
        title: "Couldn't load this week",
        message: friendlyError(error),
        detail: errorDetail(error),
        action: retry,
      );
    }

    // A saved copy on screen because in4SIT couldn't be reached (or isn't
    // signed in to yet): say so, and how old it is.
    Widget? banner;
    if (saved != null && (offline != null || error != null)) {
      final failed = offline == null || offline.phase == SessionPhase.failed;
      final why = offline == null
          ? friendlyError(error!)
          : failed
              ? "Couldn't reach SIT."
              : 'Signing in to SIT…';
      banner = Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.dense, Space.page, 0),
        child: StatusBanner(
          tone: failed ? Tone.warning : Tone.neutral,
          icon: failed ? Icons.cloud_off : Icons.sync,
          title: 'Saved timetable',
          message: '$why ${updatedAgo(saved.fetchedAt)}.',
          action: !failed
              ? null
              : offline == null
                  ? TextButton(onPressed: () => viewModel.refresh(monday), child: const Text('Retry'))
                  : TextButton(onPressed: _signInAgain, child: const Text('Retry')),
        ),
      );
    }

    return Column(
      children: [
        RefreshStrip(active: loading || (offline != null && offline.busy)),
        if (banner != null) banner,
        Expanded(child: WeekGrid(monday: monday, week: week, palette: CoursePalette(timetable.colours))),
      ],
    );
  }

  void _signInAgain() => ref.read(sessionControllerProvider.notifier).ensureSignedIn();

  Widget _signInAgainButton() => FilledButton.icon(
        onPressed: _signInAgain,
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      );

  @override
  Widget build(BuildContext context) {
    final monday = _weekStart(_page);
    final thisWeek = _page == _initialPage;
    final loading = ref.watch(timetableViewModelProvider).loading.contains(monday);

    return AppScaffold(
      appBar: thumbAppBar(
        'Timetable',
        subtitle: [
          if (thisWeek) 'This week',
          // The academic week for the shown week, from SIT's calendar.
          if (ref.watch(academicCalendarProvider).valueOrNull?.positionOf(monday) case final p?)
            'Week ${p.week.number}${p.week.phase == WeekPhase.study ? '' : ' (${phaseLabel(p.week.phase).toLowerCase()})'}',
          _weekLabel(monday),
        ].join(' · '),
      ),
      // Week navigation sits under the thumb; swiping left/right works too.
      bottomNavigationBar: ThumbBar(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ThumbIconButton(tooltip: 'Previous week', icon: Icons.chevron_left, onPressed: () => _goToPage(_page - 1)),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonal(
                onPressed: thisWeek ? null : () => _goToPage(_initialPage),
                child: Text(thisWeek ? 'This week' : 'Back to this week', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            ThumbIconButton(tooltip: 'Next week', icon: Icons.chevron_right, onPressed: () => _goToPage(_page + 1)),
            const SizedBox(width: 8),
            ThumbIconButton(
              tooltip: 'Refresh',
              icon: Icons.refresh,
              onPressed: widget.offline != null
                  ? (widget.offline!.busy ? null : _signInAgain)
                  : loading
                      ? null
                      : () => ref.read(timetableViewModelProvider.notifier).refresh(monday),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (page) => setState(() => _page = page),
        itemBuilder: (_, page) => _buildWeekPage(page),
      ),
    );
  }
}
