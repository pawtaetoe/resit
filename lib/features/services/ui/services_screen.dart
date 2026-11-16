import 'package:flutter/material.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/features/calendar/ui/academic_calendar_screen.dart';
import 'package:resit/features/exams/ui/academic_progress_screen.dart';
import 'package:resit/features/exams/ui/exam_results_screen.dart';
import 'package:resit/features/lms/ui/courses_screen.dart';
import 'package:resit/features/room_booking/ui/dashboard_screen.dart';
import 'package:resit/features/room_booking/ui/manage_booking_screen.dart';
import 'package:resit/features/timetable/ui/timetable_screen.dart';

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
          padding: const EdgeInsets.fromLTRB(Space.page, Space.section, Space.page, Space.section),
          children: [
            Text('Services', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: Space.section),
            // Everyday things first, then results, then room booking.
            const SectionLabel('Classes'),
            ..._group([
              _TaskTile(
                icon: Icons.view_week_outlined,
                title: 'Timetable',
                subtitle: 'Your weekly class schedule from in4SIT',
                onTap: () => _open(context, const TimetableScreen()),
              ),
              _TaskTile(
                icon: Icons.menu_book_outlined,
                title: 'xSiTe courses',
                subtitle: 'Course content, your progress and what to do next',
                onTap: () => _open(context, const CoursesScreen()),
              ),
              _TaskTile(
                icon: Icons.calendar_month_outlined,
                title: 'Academic calendar',
                subtitle: 'Term dates, recess, finals and holidays',
                onTap: () => _open(context, const AcademicCalendarScreen()),
              ),
            ]),
            const SizedBox(height: Space.section),
            const SectionLabel('Results'),
            ..._group([
              _TaskTile(
                icon: Icons.grading_outlined,
                title: 'Exam results',
                subtitle: 'Result slip for each term: grades and GPA',
                onTap: () => _open(context, const ExamResultsScreen()),
              ),
              _TaskTile(
                icon: Icons.insights_outlined,
                title: 'Academic progress',
                subtitle: 'Charts of your GPA, credits and grades over time',
                onTap: () => _open(context, const AcademicProgressScreen()),
              ),
            ]),
            const SizedBox(height: Space.section),
            const SectionLabel('Room booking'),
            ..._group([
              _TaskTile(
                icon: Icons.meeting_room_outlined,
                title: 'Book a room',
                subtitle: 'Find a free discussion or meeting room',
                onTap: () => _open(context, const DashboardScreen()),
              ),
              _TaskTile(
                icon: Icons.event_note_outlined,
                title: 'My bookings',
                subtitle: 'See upcoming and past bookings, or cancel one',
                onTap: () => _open(context, const ManageBookingScreen()),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Cards with the standard gap between them.
List<Widget> _group(List<Widget> tiles) => [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(height: Space.card),
        tiles[i],
      ],
    ];

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
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
