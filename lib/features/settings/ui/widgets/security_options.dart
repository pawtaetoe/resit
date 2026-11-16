import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/section_label.dart';

/// The app lock and whether the password is kept on the device.
class SecurityOptions extends ConsumerWidget {
  /// The password is kept on the device.
  final bool remember;

  /// A sign-in is running: the password choice can't change now.
  final bool busy;

  final ValueChanged<bool> onRememberChanged;

  const SecurityOptions({super.key, required this.remember, required this.busy, required this.onRememberChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lock = ref.watch(appLockProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Security'),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (lock.supported)
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('App lock'),
                  subtitle: const Text('Ask for your fingerprint, face or device PIN when reSIT opens, '
                      'and after 30 seconds away.'),
                  value: lock.enabled,
                  onChanged: (on) async {
                    final ok = await ref.read(appLockProvider.notifier).setEnabled(on);
                    if (!ok && context.mounted) {
                      showError(context, "Couldn't confirm it's you, so the app lock wasn't changed.");
                    }
                  },
                ),
              if (lock.supported) const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.password),
                title: const Text('Remember my password'),
                subtitle: Text(remember
                    ? 'Kept on this device, encrypted, so the app signs you back in whenever SIT times you out.'
                    : 'Not kept. After the app is closed you enter it again (SIT may also ask for MFA).'),
                value: remember,
                onChanged: busy ? null : onRememberChanged,
              ),
            ],
          ),
        ),
        if (lock.supported && !lock.enabled && remember)
          Padding(
            padding: const EdgeInsets.only(top: Space.dense),
            child: Text(
              'Tip: turn on the app lock so someone else holding your phone can\'t open reSIT.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
