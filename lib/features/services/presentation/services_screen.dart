import 'package:flutter/material.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/calendar/presentation/academic_calendar_screen.dart';
import 'package:resit/features/exams/presentation/exam_results_screen.dart';
import 'package:resit/features/room_booking/presentation/dashboard_screen.dart';
import 'package:resit/features/room_booking/presentation/manage_booking_screen.dart';
import 'package:resit/features/timetable/presentation/timetable_screen.dart';

/// Services tab: one card per task, grouped by what it's for.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            Text('Services', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const SectionLabel('Room booking'),
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
            const SectionLabel('Classes & exams'),
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
            const SizedBox(height: 8),
            _TaskTile(
              icon: Icons.calendar_month_outlined,
              title: 'Academic calendar',
              subtitle: 'Term dates, recess, finals and holidays',
              onTap: () => _open(context, const AcademicCalendarScreen()),
            ),
          ],
        ),
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
