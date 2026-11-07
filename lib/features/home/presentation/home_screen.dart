import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/room_booking/data/quota.dart';
import 'package:resit/features/room_booking/presentation/manage_booking_screen.dart';
import 'package:resit/features/services/presentation/overview_grid.dart';
import 'package:resit/features/timetable/data/timetable_service.dart';
import 'package:resit/features/timetable/data/upcoming_classes.dart';
import 'package:resit/features/timetable/presentation/timetable_screen.dart';

/// Home: the dashboard. Sign-in status only when there's something to do,
/// what's up next (class, booking), and the overview of the trimester,
/// credits and GPA. The tasks themselves are on the Services tab.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(upcomingClassesProvider);
    ref.invalidate(nextBookingProvider);
    ref.invalidate(academicCalendarProvider);
    await Future.wait([
      ref.read(upcomingClassesProvider.future).catchError((_) => const <ClassSession>[]),
      ref.read(nextBookingProvider.future).catchError((_) => null),
      ref.read(academicCalendarProvider.future).then((_) {}).catchError((_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final signedIn = ref.watch(authStateProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.page, Space.section, Space.page, Space.section),
            children: [
              // The wordmark's colours, as in the logo: "re" teal, "SIT" navy.
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 're', style: TextStyle(color: theme.colorScheme.secondary)),
                  TextSpan(text: 'SIT', style: TextStyle(color: theme.colorScheme.primary)),
                ]),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                semanticsLabel: 'reSIT',
              ),
              // What the app is, until it's in use.
              if (!signedIn) ...[
                const SizedBox(height: 4),
                Text(
                  'Rooms, classes, results and xSiTe at SIT, in one place.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: Space.page),
              // Only shown when there's something to act on (not signed in
              // yet, or signing in); when all is well it stays out of the way.
              const _SessionBanner(),
              const _UpNextCard(),
              // At a glance: trimester week, countdowns, credits, GPA, graduation.
              const OverviewGrid(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells the user up front when they're not signed in (and what the app is),
/// so they don't find out only after opening a feature.
class _SessionBanner extends ConsumerWidget {
  const _SessionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authStateProvider)) return const SizedBox.shrink();
    final restoring = ref.watch(sessionRestoringProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section),
      child: restoring
          ? const StatusBanner(
              tone: Tone.info,
              icon: Icons.sync,
              title: 'Signing you back in…',
              message: 'Checking your saved sign-in.',
            )
          : StatusBanner(
              tone: Tone.info,
              icon: Icons.waving_hand_outlined,
              title: 'Sign in to get started',
              message: 'An unofficial app for SIT students. Sign in once with your SIT account; '
                  'your password stays on this device.',
              action: TextButton(
                onPressed: () => ref.read(homeTabProvider.notifier).state = AppTab.account,
                child: const Text('Sign in'),
              ),
            ),
    );
  }
}

String _dayLabel(DateTime day, DateTime now) => DateUtils.isSameDay(day, now)
    ? 'Today'
    : DateUtils.isSameDay(day, now.add(const Duration(days: 1)))
        ? 'Tomorrow'
        : DateFormat('EEE d MMM').format(day);

/// What's up next: the class on now (if any), the next class and the next
/// room booking, in one card. Classes come from the saved in4SIT timetable,
/// shown straight away and moved on by itself as classes end. Hidden when
/// there's nothing to show.
class _UpNextCard extends ConsumerStatefulWidget {
  const _UpNextCard();

  @override
  ConsumerState<_UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends ConsumerState<_UpNextCard> {
  late final Timer _tick;

  /// When the timetable was last re-read because every saved class had
  /// ended; at most once every 10 minutes, so a failing in4SIT can't make
  /// it retry in a loop.
  DateTime? _lastReread;

  @override
  void initState() {
    super.initState();
    // Re-checks every minute, so the current and next class stay up to date.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(upcomingClassesProvider);
    final sessions = async.valueOrNull ?? ref.watch(savedUpcomingClassesProvider).valueOrNull ?? const [];
    final booking = ref.watch(nextBookingProvider).valueOrNull;
    final now = DateTime.now();
    final (:current, :next) = currentAndNextClass(sessions, now);

    // Every class read last time has ended: read the timetable again.
    final last = _lastReread;
    if (current == null &&
        next == null &&
        sessions.isNotEmpty &&
        async.hasValue &&
        ref.read(authStateProvider) &&
        (last == null || now.difference(last) > const Duration(minutes: 10))) {
      _lastReread = now;
      Future.microtask(() => ref.invalidate(upcomingClassesProvider));
    }
    if (current == null && next == null && booking == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final fg = theme.colorScheme.onPrimaryContainer;
    const time = ClassSession.formatMinutes;

    Widget row({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) =>
        ListTile(
          onTap: onTap,
          leading: Icon(icon, color: fg),
          title: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
          subtitle: Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          trailing: Icon(Icons.chevron_right, color: fg),
        );

    Widget classRow(ClassSession c, {required bool onNow}) {
      final when = onNow
          ? 'Now, until ${time(c.endMin)}'
          : '${_dayLabel(c.date, now)}, ${time(c.startMin)} – ${time(c.endMin)}';
      final where = c.location.trim();
      final what = [c.courseCode, if (c.component.isNotEmpty) c.component].join(' ');
      return row(
        icon: onNow ? Icons.play_circle_outline : Icons.class_outlined,
        title: '${onNow ? 'Now' : 'Next class'}: $what',
        subtitle: where.isEmpty ? when : '$when · $where',
        // Opens the timetable at the class's own week.
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimetableScreen(initialDate: c.date))),
      );
    }

    final rows = <Widget>[
      if (current != null) classRow(current, onNow: true),
      if (next != null) classRow(next, onNow: false),
      if (booking != null)
        row(
          icon: Icons.meeting_room_outlined,
          title: 'Booked: ${booking.roomName}',
          subtitle: switch (bookingStart(booking)) {
            final start? => '${_dayLabel(start, now)}, ${booking.timeRange.replaceAll('-', ' – ')}',
            null => '${booking.date}, ${booking.timeRange}',
          },
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageBookingScreen())),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Up next'),
        TintedCard(
          color: theme.colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: Space.inset, endIndent: Space.inset, color: fg.withValues(alpha: 0.2)),
                rows[i],
              ],
            ],
          ),
        ),
      ],
      ),
    );
  }
}
