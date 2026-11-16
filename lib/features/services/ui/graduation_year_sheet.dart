import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/calendar/calendar_providers.dart';
import 'package:resit/features/calendar/domain/academic_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pick the graduation year (students rarely know the exact day): the
/// countdown then runs to the Friday ending Trimester 3 finals that year.
Future<void> pickGraduationYear(BuildContext context, WidgetRef ref, int? current) async {
  final now = DateTime.now();
  // A year whose graduation day has passed can't be picked.
  final first = graduationDay(now.year, ref.read(academicCalendarProvider).valueOrNull).date.isBefore(now)
      ? now.year + 1
      : now.year;
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('When do you finish?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Pick the year of your last trimester. The countdown runs to the last day of finals in '
                'Trimester 3 that year (July or August), from SIT\'s academic calendar.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Space.page),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var y = first; y <= first + 5; y++)
                    ChoiceChip(
                      label: Text('$y'),
                      selected: y == current,
                      onSelected: (_) => Navigator.pop(context, y),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (picked == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('graduation_year', picked);
  await prefs.remove('graduation_date');
  ref.invalidate(graduationYearProvider);
}

/// Change or clear the graduation year.
Future<void> editGraduationYear(BuildContext context, WidgetRef ref, int year, DateTime date, bool estimated) async {
  final choice = await showChoiceSheet<String>(
    context,
    icon: Icons.workspace_premium_outlined,
    title: 'Finishing in $year',
    message: 'Counting down to ${DateFormat('EEEE d MMMM yyyy').format(date)}, your last day of finals '
        '(the end of Trimester 3 finals)'
        '${estimated ? ' (estimated: SIT\'s calendar doesn\'t list $year yet)' : ''}.',
    choices: const [
      SheetChoice('change', 'Change year', icon: Icons.edit_calendar_outlined, primary: true),
      SheetChoice('clear', 'Remove the countdown', icon: Icons.delete_outline, danger: true),
    ],
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'change') return pickGraduationYear(context, ref, year);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('graduation_year');
  await prefs.remove('graduation_date');
  ref.invalidate(graduationYearProvider);
}
