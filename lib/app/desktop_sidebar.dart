import 'package:flutter/material.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/calendar/ui/academic_calendar_screen.dart';
import 'package:resit/features/exams/ui/academic_progress_screen.dart';
import 'package:resit/features/exams/ui/exam_results_screen.dart';
import 'package:resit/features/lms/ui/courses_screen.dart';
import 'package:resit/features/lms/ui/xsite_calendar_screen.dart';
import 'package:resit/features/room_booking/ui/dashboard_screen.dart';
import 'package:resit/features/room_booking/ui/manage_booking_screen.dart';
import 'package:resit/features/timetable/ui/timetable_screen.dart';
import 'package:resit/features/home/ui/home_screen.dart';
import 'package:resit/features/settings/ui/settings_screen.dart';

/// The desktop sidebar: everything in Services listed directly, grouped by
/// the SIT system it comes from.
final List<DesktopDestination> desktopDestinations = [
  DesktopDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home', builder: (_) => const HomeScreen()),
  DesktopDestination(
      group: 'in4SIT',
      icon: Icons.view_week_outlined,
      selectedIcon: Icons.view_week,
      label: 'Timetable',
      builder: (_) => const TimetableScreen()),
  DesktopDestination(
      group: 'in4SIT',
      icon: Icons.grading_outlined,
      selectedIcon: Icons.grading,
      label: 'Exam results',
      builder: (_) => const ExamResultsScreen()),
  DesktopDestination(
      group: 'in4SIT',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      label: 'Academic progress',
      builder: (_) => const AcademicProgressScreen()),
  DesktopDestination(
      group: 'xSiTe',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Courses',
      builder: (_) => const CoursesScreen()),
  DesktopDestination(
      group: 'xSiTe',
      icon: Icons.event_outlined,
      selectedIcon: Icons.event,
      label: 'Calendar',
      builder: (_) => const XsiteCalendarScreen()),
  DesktopDestination(
      group: 'Room booking',
      icon: Icons.meeting_room_outlined,
      selectedIcon: Icons.meeting_room,
      label: 'Book a room',
      builder: (_) => const DashboardScreen()),
  DesktopDestination(
      group: 'Room booking',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: 'My bookings',
      builder: (_) => const ManageBookingScreen()),
  DesktopDestination(
      group: 'General',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Academic calendar',
      builder: (_) => const AcademicCalendarScreen()),
  DesktopDestination(
      group: 'General',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: 'Account',
      builder: (_) => const SettingsScreen()),
];

/// The wordmark at the top of the desktop sidebar.
class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 're', style: TextStyle(color: theme.colorScheme.secondary)),
              TextSpan(text: 'SIT', style: TextStyle(color: theme.colorScheme.primary)),
            ]),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            semanticsLabel: 'reSIT',
          ),
          Text('SIT, in one place',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
