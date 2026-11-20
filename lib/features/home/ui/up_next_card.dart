import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';
import 'package:resit/features/timetable/timetable_providers.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/features/room_booking/ui/manage_booking_screen.dart';
import 'package:resit/features/timetable/ui/timetable_screen.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/features/lms/ui/class_meeting_button.dart';

String _dayLabel(DateTime day, DateTime now) => DateUtils.isSameDay(day, now)
    ? 'Today'
    : DateUtils.isSameDay(day, now.add(const Duration(days: 1)))
        ? 'Tomorrow'
        : DateFormat('EEE d MMM').format(day);

/// What's up next: the class on now (if any), the next class and the next
/// room booking, in one card. Classes come from the saved in4SIT timetable,
/// shown straight away and moved on by itself as classes end. Hidden when
/// there's nothing to show.
class UpNextCard extends ConsumerStatefulWidget {
  const UpNextCard({super.key});

  @override
  ConsumerState<UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends ConsumerState<UpNextCard> {
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

    final chevron = Icon(Icons.chevron_right, color: fg);
    Widget row(
            {required IconData icon,
            required String title,
            required String subtitle,
            required VoidCallback onTap,
            Widget? trailing}) =>
        ListTile(
          onTap: onTap,
          leading: Icon(icon, color: fg),
          title: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
          subtitle: Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          trailing: trailing ?? chevron,
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
        // An online class: "Join" when its module's announcements give the link.
        trailing: ClassMeetingButton(session: c, fallback: chevron),
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
        // How fresh the classes are, so an old saved timetable isn't taken as live.
        if (ref.watch(upcomingClassesUpdatedProvider).valueOrNull case final at? when current != null || next != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              DesktopScope.of(context) ? updatedAgo(at, now) : '${updatedAgo(at, now)} · pull down to refresh',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
      ),
    );
  }
}
