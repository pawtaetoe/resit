import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/lms/domain/meeting_links.dart';
import 'package:resit/features/lms/meeting_providers.dart';
import 'package:resit/features/lms/ui/meeting_actions.dart';
import 'package:resit/features/timetable/domain/class_session.dart';

/// "Join" on an online class's row, when the module's xSiTe announcements
/// give a meeting link; [fallback] otherwise (and while looking). Only an
/// online class, when signed in, looks: other rows cost nothing.
class ClassMeetingButton extends ConsumerWidget {
  final ClassSession session;
  final Widget fallback;
  const ClassMeetingButton({super.key, required this.session, required this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOnlineLocation(session.location) || !ref.watch(authStateProvider)) return fallback;
    final link = ref.watch(moduleMeetingLinkProvider(session.courseCode)).valueOrNull;
    if (link == null) return fallback;
    final title = [session.courseCode, if (session.component.isNotEmpty) session.component].join(' ');
    return MeetingJoinButton(link, title: title);
  }
}
