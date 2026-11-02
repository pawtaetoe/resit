import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/exams/presentation/exam_results_screen.dart';
import 'package:resit/features/room_booking/presentation/dashboard_screen.dart';
import 'package:resit/features/room_booking/presentation/manage_booking_screen.dart';
import 'package:resit/features/timetable/presentation/timetable_screen.dart';

/// Home: sign-in status at the top, then one card per task.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            Text('reSIT', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Rooms and classes at SIT, in one place.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            const _SessionBanner(),
            const SizedBox(height: 24),
            const _SectionLabel('Room booking'),
            _TaskTile(
              icon: Icons.add_business_outlined,
              title: 'Book a room',
              subtitle: 'Find a free room for a time slot',
              onTap: () => _open(context, const DashboardScreen()),
            ),
            const SizedBox(height: 8),
            _TaskTile(
              icon: Icons.event_note_outlined,
              title: 'My bookings',
              subtitle: 'See upcoming and past bookings, or cancel one',
              onTap: () => _open(context, const ManageBookingScreen()),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Classes & exams'),
            _TaskTile(
              icon: Icons.calendar_view_week_outlined,
              title: 'Timetable',
              subtitle: 'Your weekly class schedule from in4SIT',
              onTap: () => _open(context, const TimetableScreen()),
            ),
            const SizedBox(height: 8),
            _TaskTile(
              icon: Icons.grading_outlined,
              title: 'Exam results',
              subtitle: 'Grades and GPA for each term',
              onTap: () => _open(context, const ExamResultsScreen()),
            ),
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
                onPressed: () => ref.read(homeTabProvider.notifier).state = 1,
                child: const Text('Sign in'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// A whole-card tap target (large and easy to hit) for one task.
class _TaskTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TaskTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
