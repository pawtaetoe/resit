import 'package:flutter/material.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/panels.dart';

/// Whether you're signed in, and as whom. When signed in, "Change" edits
/// the saved login.
class AccountStatusBanner extends StatelessWidget {
  final bool signedIn;
  final SessionPhase phase;
  final String? savedUsername;

  /// The password is kept on the device.
  final bool remember;

  /// The saved login is being changed: no "Change" button.
  final bool editing;

  /// A sign-in is running: "Change" is disabled.
  final bool busy;

  final VoidCallback onChange;

  const AccountStatusBanner({
    super.key,
    required this.signedIn,
    required this.phase,
    required this.savedUsername,
    required this.remember,
    required this.editing,
    required this.busy,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    if (signedIn) {
      return StatusBanner(
        tone: Tone.success,
        icon: Icons.verified_user_outlined,
        title: savedUsername != null ? 'Signed in as $savedUsername' : 'Signed in',
        message: remember
            ? 'The app signs you back in automatically when your session expires.'
            : 'Signed in until you close the app.',
        action: editing ? null : TextButton(onPressed: busy ? null : onChange, child: const Text('Change')),
      );
    }
    final (Tone tone, IconData icon, String title, String message) = switch (phase) {
      SessionPhase.checking => (Tone.info, Icons.sync, 'Checking your session…', 'This only takes a moment.'),
      SessionPhase.signingIn => (Tone.info, Icons.sync, 'Signing you in…', 'Using your saved login.'),
      SessionPhase.failed => (Tone.danger, Icons.error_outline, "Couldn't sign you in", 'See the message below.'),
      _ => (Tone.info, Icons.person_outline, 'Not signed in', 'Sign in below to use your timetable, results and bookings.'),
    };
    return StatusBanner(tone: tone, icon: icon, title: title, message: message);
  }
}
