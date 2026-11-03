import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/features/calendar/data/academic_calendar.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';

class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _PlacedSession {
  final ClassSession session;
  final int lane;
  final int laneCount;

  _PlacedSession(this.session, this.lane, this.laneCount);
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  // The week pager is "infinite": page 1000 is the current week.
  static const _initialPage = 1000;
  static const _timeColumnWidth = 40.0;
  static const _hourHeight = 60.0;
  static const _dayCount = 5; // Monday to Friday

  final _pageController = PageController(initialPage: _initialPage);
  int _page = _initialPage;

  // Weeks are fetched one at a time (the server keeps the page state) and
  // cached by their Monday.
  final Map<DateTime, WeekSchedule> _weeks = {};
  final Map<DateTime, Object> _weekErrors = {};
  final Set<DateTime> _loadingWeeks = {};
  MfaChallenge? _mfaChallenge;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadWeek(DateTime monday, {bool force = false}) async {
    if (_loadingWeeks.contains(monday)) return;
    if (!force && (_weeks.containsKey(monday) || _weekErrors.containsKey(monday))) return;

    setState(() {
      _loadingWeeks.add(monday);
      _weekErrors.remove(monday);
      if (force) _weeks.clear();
    });

    final service = ref.read(timetableServiceProvider);
    Future<WeekSchedule> fetch() => service.week(
          monday,
          onMfaChallenge: (challenge) {
            if (mounted) setState(() => _mfaChallenge = challenge);
          },
        );

    try {
      if (force) service.reset();
      WeekSchedule week;
      try {
        week = await fetch();
      } on SessionExpiredException {
        // in4SIT's sign-in failed: sign in afresh automatically, then retry
        // once, instead of asking the user to do it.
        final signedIn = await ref.read(sessionControllerProvider.notifier).ensureSignedIn(force: true);
        if (!signedIn) rethrow;
        service.reset();
        week = await fetch();
      }
      if (!mounted) return;
      setState(() => _weeks[monday] = week);
    } catch (e) {
      if (!mounted) return;
      setState(() => _weekErrors[monday] = e);
    } finally {
      if (mounted) {
        setState(() {
          _loadingWeeks.remove(monday);
          _mfaChallenge = null;
        });
      }
    }
  }

  DateTime _weekStart(int page) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day + (page - _initialPage) * 7);
  }

  String _weekLabel(DateTime monday) {
    final friday = DateTime(monday.year, monday.month, monday.day + _dayCount - 1);
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

  Color _courseColor(String code) {
    final colors = Colors.primaries;
    return colors[code.hashCode.abs() % colors.length].shade700;
  }

  /// White or black, whichever reads better on [background]. On every course
  /// colour this gives at least 4.5:1 contrast (WCAG AA), in light and dark
  /// mode alike.
  static Color _textOn(Color background) {
    final l = background.computeLuminance();
    final onWhite = 1.05 / (l + 0.05);
    final onBlack = (l + 0.05) / 0.05;
    return onWhite >= onBlack ? Colors.white : Colors.black;
  }

  /// Lays out one day's sessions side by side where they overlap in time.
  List<_PlacedSession> _layoutDay(List<ClassSession> sessions) {
    final sorted = [...sessions]..sort((a, b) => a.startMin.compareTo(b.startMin));
    final placed = <_PlacedSession>[];

    var cluster = <ClassSession>[];
    var clusterEnd = 0;

    void flush() {
      final laneEnds = <int>[];
      final lanes = <int>[];
      for (final s in cluster) {
        var lane = laneEnds.indexWhere((end) => end <= s.startMin);
        if (lane == -1) {
          laneEnds.add(s.endMin);
          lane = laneEnds.length - 1;
        } else {
          laneEnds[lane] = s.endMin;
        }
        lanes.add(lane);
      }
      for (var i = 0; i < cluster.length; i++) {
        placed.add(_PlacedSession(cluster[i], lanes[i], laneEnds.length));
      }
      cluster = [];
    }

    for (final s in sorted) {
      if (cluster.isNotEmpty && s.startMin >= clusterEnd) flush();
      cluster.add(s);
      clusterEnd = cluster.length == 1 ? s.endMin : (s.endMin > clusterEnd ? s.endMin : clusterEnd);
    }
    if (cluster.isNotEmpty) flush();
    return placed;
  }

  void _showDetails(ClassSession s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Sized to its content (not capped at half the screen), so larger text
      // sizes aren't cut off; it scrolls if it's taller than the screen.
      isScrollControlled: true,
      // Keeps the details clear of the system navigation bar.
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.courseCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const SizedBox(height: 12),
              _detailRow(Icons.class_outlined, '${s.component} · ${s.section}'),
              _detailRow(Icons.calendar_today_outlined, DateFormat('EEEE, d MMM yyyy').format(s.date)),
              _detailRow(Icons.schedule, s.timeLabel),
              if (s.location.isNotEmpty) _detailRow(Icons.place_outlined, s.location),
              if (s.coinciding) ...[
                const SizedBox(height: 8),
                const StatusPill(
                  label: 'Clashes with another class',
                  tone: Tone.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      );

  Widget _buildGrid(DateTime monday, WeekSchedule? week) {
    final today = DateTime.now();
    final sessions = week?.sessions ?? const <ClassSession>[];

    final minStart = sessions.map((s) => s.startMin).fold<int>(8 * 60, (a, b) => a < b ? a : b);
    final maxEnd = sessions.map((s) => s.endMin).fold<int>(18 * 60, (a, b) => a > b ? a : b);
    final startHour = minStart ~/ 60;
    final endHour = (maxEnd + 59) ~/ 60;
    final gridHeight = (endHour - startHour) * _hourHeight;

    return LayoutBuilder(builder: (context, constraints) {
      final colWidth = (constraints.maxWidth - _timeColumnWidth) / _dayCount;
      final scheme = Theme.of(context).colorScheme;
      final muted = scheme.onSurfaceVariant;
      final nowDate = DateTime(today.year, today.month, today.day);
      final todayIndex = nowDate.difference(monday).inDays;
      final nowMin = today.hour * 60 + today.minute;
      final showNow = todayIndex >= 0 && todayIndex < _dayCount && nowMin >= startHour * 60 && nowMin <= endHour * 60;

      final header = Row(
        children: [
          const SizedBox(width: _timeColumnWidth),
          for (var d = 0; d < _dayCount; d++)
            Builder(builder: (_) {
              final date = DateTime(monday.year, monday.month, monday.day + d);
              final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
              return SizedBox(
                width: colWidth,
                child: Column(
                  children: [
                    Text(DateFormat('E').format(date),
                        style: TextStyle(fontSize: 11, color: isToday ? scheme.primary : muted)),
                    const SizedBox(height: 2),
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: isToday ? scheme.primary : Colors.transparent,
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isToday ? scheme.onPrimary : null,
                        ),
                      ),
                    ),
                    if (date.day == 1 || d == 0)
                      Text(DateFormat('MMM').format(date), style: TextStyle(fontSize: 10, color: muted)),
                  ],
                ),
              );
            }),
        ],
      );

      final grid = SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            for (var h = startHour; h <= endHour; h++)
              Positioned(
                top: (h - startHour) * _hourHeight,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    SizedBox(
                      width: _timeColumnWidth,
                      child: Transform.translate(
                        offset: const Offset(0, -7),
                        child: Text(
                          '${h.toString().padLeft(2, '0')}:00',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(height: 1, color: scheme.outlineVariant)),
                  ],
                ),
              ),
            for (var d = 0; d < _dayCount; d++) ...[
              if (d > 0)
                Positioned(
                  left: _timeColumnWidth + d * colWidth,
                  top: 0,
                  bottom: 0,
                  child: VerticalDivider(width: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              if (week != null)
                for (final placed in _layoutDay(week.forDay(d)))
                  Builder(builder: (_) {
                    final s = placed.session;
                    final laneWidth = colWidth / placed.laneCount;
                    final color = _courseColor(s.courseCode);
                    return Positioned(
                      left: _timeColumnWidth + d * colWidth + placed.lane * laneWidth + 1,
                      top: (s.startMin - startHour * 60) / 60 * _hourHeight + 1,
                      width: laneWidth - 2,
                      height: (s.endMin - s.startMin) / 60 * _hourHeight - 2,
                      child: GestureDetector(
                        onTap: () => _showDetails(s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                            border: s.coinciding ? Border.all(color: Colors.orangeAccent, width: 1.5) : null,
                          ),
                          child: Semantics(
                            button: true,
                            label: '${s.courseCode} ${s.component}, ${s.timeLabel}, ${s.location}',
                            excludeSemantics: true,
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: '${s.courseCode}\n',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                                TextSpan(text: '${s.component}\n${s.location}'),
                              ]),
                              overflow: TextOverflow.clip,
                              style: TextStyle(color: _textOn(color), fontSize: 9, height: 1.2),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
            ],
            if (showNow)
              Positioned(
                left: _timeColumnWidth + todayIndex * colWidth - 4,
                width: colWidth + 4,
                top: (nowMin - startHour * 60) / 60 * _hourHeight - 4,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      CircleAvatar(radius: 4, backgroundColor: scheme.error),
                      Expanded(child: Container(height: 2, color: scheme.error)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

      return Column(
        children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: header),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(child: grid)),
        ],
      );
    });
  }

  Widget _buildWeekPage(int page) {
    final monday = _weekStart(page);
    final week = _weeks[monday];
    final error = _weekErrors[monday];
    final loading = _loadingWeeks.contains(monday);

    if (week == null && error == null && !loading) {
      // Not requested yet: fetch it once this page is built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadWeek(monday);
      });
    }

    // MFA from in4SIT's own sign-in, or from the automatic sign-in retry.
    final sessionState = ref.watch(sessionControllerProvider);
    final challenge = _mfaChallenge ?? (sessionState.phase == SessionPhase.signingIn ? sessionState.challenge : null);
    if (challenge != null && loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MfaCard(challenge: challenge),
        ),
      );
    }

    if (week == null && error != null) {
      final session = isSessionError(error);
      final retry = FilledButton.icon(
        onPressed: () => _loadWeek(monday, force: true),
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      );
      return MessageView(
        icon: session ? Icons.lock_clock : Icons.cloud_off,
        tone: Tone.danger,
        title: session ? "Couldn't sign in to in4SIT" : "Couldn't load this week",
        message: friendlyError(error),
        detail: errorDetail(error),
        action: retry,
      );
    }

    return Column(
      children: [
        SizedBox(height: 3, child: loading ? const LinearProgressIndicator() : null),
        Expanded(child: _buildGrid(monday, week)),
        if (week != null && week.sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: StatusPill(label: 'No classes this week', tone: Tone.neutral, icon: Icons.free_breakfast_outlined),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monday = _weekStart(_page);
    final thisWeek = _page == _initialPage;
    final loading = _loadingWeeks.contains(monday);
    final navStyle = IconButton.styleFrom(minimumSize: const Size(48, 52));

    return Scaffold(
      appBar: thumbAppBar(
        'Timetable',
        subtitle: Text(
          [
            if (thisWeek) 'This week',
            // The academic week for the shown week, from SIT's calendar.
            if (ref.watch(academicCalendarProvider).valueOrNull?.positionOf(monday) case final p?)
              'Week ${p.week.number}${p.week.phase == WeekPhase.study ? '' : ' (${phaseLabel(p.week.phase).toLowerCase()})'}',
            _weekLabel(monday),
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      // Week navigation sits under the thumb; swiping left/right works too.
      bottomNavigationBar: ThumbBar(
        child: Row(
          children: [
            IconButton(
              style: navStyle,
              tooltip: 'Previous week',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _goToPage(_page - 1),
            ),
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: thisWeek ? null : () => _goToPage(_initialPage),
                child: Text(thisWeek ? 'This week' : 'Back to this week', overflow: TextOverflow.ellipsis),
              ),
            ),
            IconButton(
              style: navStyle,
              tooltip: 'Next week',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _goToPage(_page + 1),
            ),
            IconButton(
              style: navStyle,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: loading ? null : () => _loadWeek(monday, force: true),
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
