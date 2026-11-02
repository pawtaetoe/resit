import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/room_booking/data/quota.dart';
import 'package:resit/features/room_booking/presentation/manage_booking_screen.dart';
import 'package:resit/features/services/presentation/overview_grid.dart';

/// Home: the dashboard. Sign-in status only when there's something to do,
/// the next booking, and the overview of the trimester, credits and GPA.
/// The tasks themselves are on the Services tab.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
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
            const SizedBox(height: 4),
            Text(
              'Rooms, classes and results at SIT, in one place.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            // Only shown when there's something to act on (not signed in yet,
            // or signing in); when all is well it stays out of the way.
            const _SessionBanner(),
            const _NextBookingCard(),
            const SizedBox(height: 16),
            // At a glance: trimester week, countdowns, credits, GPA, graduation.
            const SectionLabel('Overview'),
            const OverviewGrid(),
          ],
        ),
      ),
    );
  }
}

/// Tells the user up front whether they're signed in, so they don't find
/// out only after opening a feature.
class _SessionBanner extends ConsumerWidget {
  const _SessionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(authStateProvider);
    final restoring = ref.watch(sessionRestoringProvider);
    if (signedIn) return const SizedBox.shrink();

    final (Tone tone, IconData icon, String title, String message) = signedIn
        ? (Tone.success, Icons.verified_user_outlined, 'Signed in', 'You can book rooms and view your timetable.')
        : restoring
            ? (Tone.info, Icons.sync, 'Restoring your session…', 'Hang on, checking your saved sign-in.')
            : (Tone.warning, Icons.info_outline, 'Not signed in', 'Sign in with your SIT account to get started.');
    final (bg, fg) = tone.colors(scheme);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(message, style: TextStyle(color: fg, fontSize: 13)),
                ],
              ),
            ),
            if (!signedIn && !restoring)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: fg),
                onPressed: () => ref.read(homeTabProvider.notifier).state = AppTab.account,
                child: const Text('Sign in'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The next confirmed room booking, so it's visible without opening
/// My bookings. Hidden when there's none or while loading.
class _NextBookingCard extends ConsumerWidget {
  const _NextBookingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(nextBookingProvider).valueOrNull;
    if (booking == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final start = bookingStart(booking);
    final now = DateTime.now();
    final when = start == null
        ? '${booking.date}, ${booking.timeRange}'
        : '${DateUtils.isSameDay(start, now) ? 'Today' : DateUtils.isSameDay(start, now.add(const Duration(days: 1))) ? 'Tomorrow' : DateFormat('EEE d MMM').format(start)}'
            ', ${booking.timeRange.replaceAll('-', ' – ')}';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: theme.colorScheme.secondaryContainer,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageBookingScreen())),
          leading: Icon(Icons.event_available, color: theme.colorScheme.onSecondaryContainer),
          title: Text('Next booking: ${booking.roomName}',
              style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSecondaryContainer)),
          subtitle: Text(when, style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
