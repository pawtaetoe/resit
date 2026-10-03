import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/widgets/mfa_card.dart';
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
  final Map<DateTime, String> _weekErrors = {};
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

    try {
      final service = ref.read(timetableServiceProvider);
      if (force) service.reset();
      final week = await service.week(
        monday,
        onMfaChallenge: (challenge) {
          if (mounted) setState(() => _mfaChallenge = challenge);
        },
      );
      if (!mounted) return;
      setState(() => _weeks[monday] = week);
    } catch (e) {
      if (!mounted) return;
      setState(() => _weekErrors[monday] = e.toString());
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
    return colors[code.hashCode.abs() % colors.length].shade600;
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
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.courseCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${s.component} • ${s.section}'),
            const SizedBox(height: 4),
            Text('${DateFormat('EEEE, d MMM yyyy').format(s.date)}  ${s.timeLabel}'),
            if (s.location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Location: ${s.location}'),
            ],
            if (s.coinciding) ...[
              const SizedBox(height: 8),
              const Text(
                'This class overlaps with another class at the same time.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
                    Text(DateFormat('E').format(date), style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                      Text(DateFormat('MMM').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3))),
                  ],
                ),
              ),
            for (var d = 0; d < _dayCount; d++) ...[
              if (d > 0)
                Positioned(
                  left: _timeColumnWidth + d * colWidth,
                  top: 0,
                  bottom: 0,
                  child: VerticalDivider(width: 1, color: Colors.grey.withValues(alpha: 0.2)),
                ),
              if (week != null)
                for (final placed in _layoutDay(week.forDay(d)))
                  Builder(builder: (_) {
                    final s = placed.session;
                    final laneWidth = colWidth / placed.laneCount;
                    return Positioned(
                      left: _timeColumnWidth + d * colWidth + placed.lane * laneWidth + 1,
                      top: (s.startMin - startHour * 60) / 60 * _hourHeight + 1,
                      width: laneWidth - 2,
                      height: (s.endMin - s.startMin) / 60 * _hourHeight - 2,
                      child: GestureDetector(
                        onTap: () => _showDetails(s),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: _courseColor(s.courseCode),
                            borderRadius: BorderRadius.circular(4),
                            border: s.coinciding ? Border.all(color: Colors.orangeAccent, width: 1.5) : null,
                          ),
                          child: Text(
                            '${s.courseCode}\n${s.component}\n${s.location}',
                            overflow: TextOverflow.clip,
                            style: const TextStyle(color: Colors.white, fontSize: 9, height: 1.15),
                          ),
                        ),
                      ),
                    );
                  }),
            ],
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

    if (_mfaChallenge != null && loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MfaCard(challenge: _mfaChallenge!),
        ),
      );
    }

    if (week == null && error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadWeek(monday, force: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(height: 3, child: loading ? const LinearProgressIndicator() : null),
        Expanded(child: _buildGrid(monday, week)),
        if (week != null && week.sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No classes this week.', style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final monday = _weekStart(_page);
    return Scaffold(
      appBar: AppBar(
        title: Text(_weekLabel(monday), style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goToPage(_page - 1),
          ),
          IconButton(
            tooltip: 'This week',
            icon: const Icon(Icons.today),
            onPressed: _page == _initialPage ? null : () => _goToPage(_initialPage),
          ),
          IconButton(
            tooltip: 'Next week',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goToPage(_page + 1),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadingWeeks.contains(monday) ? null : () => _loadWeek(monday, force: true),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (page) => setState(() => _page = page),
        itemBuilder: (_, page) => _buildWeekPage(page),
      ),
    );
  }
}
