import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:resit/features/lms/ui/sections/more_text.dart';

String _when(DateTime d) => DateFormat('EEE d MMM, HH:mm').format(d);

/// A survey: when it's open, whether it's anonymous, its description, and a
/// button to take it on xSiTe.
class SurveyCard extends StatelessWidget {
  final Survey survey;
  final DateTime now;
  const SurveyCard({super.key, required this.survey, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = survey;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.card),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (s.isClosed(now))
                    StatusPill(label: 'Closed ${_when(s.end!)}', tone: Tone.neutral)
                  else if (s.opensLater(now))
                    StatusPill(label: 'Opens ${_when(s.start!)}', tone: Tone.neutral, icon: Icons.schedule)
                  else
                    StatusPill(
                      label: s.end == null ? 'Open' : 'Open until ${_when(s.end!)}',
                      tone: Tone.info,
                      icon: Icons.schedule,
                    ),
                  if (s.isAnonymous) const StatusPill(label: 'Anonymous', tone: Tone.neutral, icon: Icons.visibility_off),
                ],
              ),
              if (s.description.isNotEmpty) ...[const SizedBox(height: 8), MoreText(s.description, lines: 3)],
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => openInBrowser(context, s.url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(s.isOpen(now) ? 'Take on xSiTe' : 'Open on xSiTe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
