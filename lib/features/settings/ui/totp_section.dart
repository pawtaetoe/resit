import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/settings/ui/widgets/live_code.dart';
import 'package:resit/features/settings/ui/widgets/totp_setup_sheet.dart';

/// Account section for automatic MFA verification codes (TOTP).
class TotpSection extends ConsumerWidget {
  const TotpSection({super.key});

  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final ok = await showChoiceSheet<bool>(
      context,
      icon: Icons.password,
      title: 'Turn off automatic codes?',
      message: 'The code secret is removed from this phone. Sign-ins will need approval on your phone again, '
          'or a code typed from another authenticator app.',
      choices: const [
        SheetChoice(true, 'Turn off', icon: Icons.delete_outline, primary: true, danger: true),
        SheetChoice(false, 'Keep it on'),
      ],
    );
    if (ok != true) return;
    await ref.read(secureStorageProvider).clearTotp();
    ref.invalidate(totpConfigProvider);
    if (context.mounted) showSuccess(context, 'Automatic codes turned off.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final config = ref.watch(totpConfigProvider).valueOrNull;
    final on = config != null;
    final (bg, fg) = (on ? Tone.success : Tone.neutral).colors(scheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: bg, foregroundColor: fg, child: const Icon(Icons.password)),
                const SizedBox(width: 12),
                Expanded(child: Text('Automatic verification codes', style: theme.textTheme.titleMedium)),
                StatusPill(label: on ? 'On' : 'Off', tone: on ? Tone.success : Tone.neutral),
              ],
            ),
            const SizedBox(height: 12),
            if (!on) ...[
              Text(
                'Let the app enter your 6-digit sign-in code itself, so you don\'t need to approve '
                'each sign-in on your phone.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => showTotpSetupSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Set up'),
              ),
            ] else ...[
              if (config.issuer != null || config.account != null)
                Text(
                  [config.issuer, config.account].whereType<String>().join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              const SizedBox(height: 8),
              LiveCode(config: config),
              const SizedBox(height: 4),
              Text(
                'Used automatically when sign-in asks for a code. For the app to be asked, make the '
                'authenticator code your default sign-in method at mysignins.microsoft.com.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => showTotpSetupSheet(context),
                      child: const Text('Replace'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      style: dangerTonal(scheme),
                      onPressed: () => _turnOff(context, ref),
                      child: const Text('Turn off'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
