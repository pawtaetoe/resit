import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/widgets/panels.dart';

/// Tells the user up front when they're not signed in (and what the app is),
/// so they don't find out only after opening a feature.
class SessionBanner extends ConsumerWidget {
  const SessionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authStateProvider)) return const SizedBox.shrink();
    final restoring = ref.watch(sessionRestoringProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.section),
      child: restoring
          ? const StatusBanner(
              tone: Tone.info,
              icon: Icons.sync,
              title: 'Signing you back in…',
              message: 'Checking your saved sign-in.',
            )
          : StatusBanner(
              tone: Tone.info,
              icon: Icons.waving_hand_outlined,
              title: 'Sign in to get started',
              message: 'An unofficial app for SIT students. Sign in once with your SIT account; '
                  'your password stays on this device.',
              action: TextButton(
                onPressed: () => ref.read(homeTabProvider.notifier).state = AppTab.account,
                child: const Text('Sign in'),
              ),
            ),
    );
  }
}
