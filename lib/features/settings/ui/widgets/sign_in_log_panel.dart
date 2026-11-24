import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';

/// Every sign-in's steps (including the timetable's), for troubleshooting.
/// Shown after a failed sign-in, or behind "Having trouble?".
class SignInTroubleshooting extends ConsumerWidget {
  /// Show the log rather than the "Having trouble?" button.
  final bool showLog;

  /// "Having trouble?" was tapped.
  final VoidCallback onShowLog;

  const SignInTroubleshooting({super.key, required this.showLog, required this.onShowLog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: ref.watch(authServiceProvider).signInLog,
      builder: (context, log, _) {
        if (log.isEmpty) return const SizedBox.shrink();
        if (!showLog) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onShowLog,
              child: const Text('Show the sign-in log'),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: Space.page),
          child: SignInLogPanel(log: log.join('\n')),
        );
      },
    );
  }
}

/// Technical sign-in log, collapsed by default: useful for troubleshooting,
/// noise for everyone else.
class SignInLogPanel extends StatelessWidget {
  final String log;
  const SignInLogPanel({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: const Text('Sign-in details'),
        subtitle: const Text('Copy these if you need help with signing in'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(log,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: log));
                showSuccess(context, 'Details copied.');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
    );
  }
}
