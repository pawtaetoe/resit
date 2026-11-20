import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';
import 'package:resit/features/timetable/timetable_providers.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/features/lms/lms_providers.dart';
import 'package:resit/features/lms/meeting_providers.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/services/ui/overview_grid.dart';
import 'package:resit/features/home/ui/desktop_home.dart';
import 'package:resit/features/home/ui/session_banner.dart';
import 'package:resit/features/home/ui/up_next_card.dart';

/// Home: the dashboard. Sign-in status only when there's something to do,
/// what's up next (class, booking), and the overview of the trimester,
/// credits and GPA. The tasks themselves are on the Services tab.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(nextBookingProvider);
    ref.invalidate(academicCalendarProvider);
    // An online class's "Join": its module's announcements are read again.
    ref.invalidate(lmsAnnouncementsProvider);
    ref.invalidate(moduleMeetingLinkProvider);
    await Future.wait([
      // Pulling down means "now": skip the timetable's 1-hour freshness window.
      if (ref.read(authStateProvider))
        ref
            .read(upcomingClassesServiceProvider)
            .load(force: true)
            .then((_) => ref.invalidate(upcomingClassesProvider))
            .catchError((_) {}),
      ref.read(nextBookingProvider.future).catchError((_) => null),
      ref.read(academicCalendarProvider.future).then((_) {}).catchError((_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final signedIn = ref.watch(authStateProvider);
    if (DesktopScope.of(context)) return DesktopHome(onRefresh: () => _refresh(ref));

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
              const SessionBanner(),
              const UpNextCard(),
              // At a glance: trimester week, countdowns, credits, GPA, graduation.
              const OverviewGrid(),
            ],
          ),
        ),
      ),
    );
  }
}
