import 'package:flutter/material.dart';
import 'package:resit/features/timetable/domain/class_session.dart';

/// A class on the week grid, in its course's [colour]: the module, the kind
/// of class and the place. Tapping it calls [onTap].
class ClassBlock extends StatelessWidget {
  final ClassSession session;
  final Color colour;
  final VoidCallback onTap;

  const ClassBlock({super.key, required this.session, required this.colour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final theme = Theme.of(context);
    // One node for screen readers, with the tap on it.
    return Semantics(
      button: true,
      label: '${s.courseCode} ${s.component}, ${s.timeLabel}, ${s.location}'
          '${s.coinciding ? ', clashes with another class' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(6),
            // A clash shows as an orange outline and a warning sign.
            border: s.coinciding ? Border.all(color: theme.colorScheme.tertiary, width: 2) : null,
          ),
          child: Text.rich(
            TextSpan(children: [
              if (s.coinciding) const TextSpan(text: '⚠ '),
              TextSpan(text: '${s.courseCode}\n', style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: '${s.component}\n${s.location}'),
            ]),
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, height: 1.2, letterSpacing: 0),
          ),
        ),
      ),
    );
  }
}
