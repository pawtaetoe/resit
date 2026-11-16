import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/adfs/totp.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/thumb_bar.dart';

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
                    child: OutlinedButton(
                      onPressed: () => showTotpSetupSheet(context),
                      child: const Text('Replace'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
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

/// The current code with a countdown, refreshed every second.
class LiveCode extends StatefulWidget {
  final TotpConfig config;
  const LiveCode({super.key, required this.config});

  @override
  State<LiveCode> createState() => _LiveCodeState();
}

class _LiveCodeState extends State<LiveCode> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    // Redraws only while it can be seen: not on another tab (TickerMode off)
    // or with the app in the background.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final code = widget.config.codeAt(now);
    final left = widget.config.secondsLeft(now);
    final half = code.length ~/ 2;
    final shown = '${code.substring(0, half)} ${code.substring(half)}';

    return Semantics(
      label: 'Current code ${code.split('').join(' ')}, changes in $left seconds',
      excludeSemantics: true,
      child: Row(
        children: [
          Text(
            shown,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              value: left / widget.config.period,
              strokeWidth: 3,
              color: left <= 5 ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(width: 6),
          Text('${left}s', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

Future<void> showTotpSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _TotpSetupSheet(),
  );
}

class _TotpSetupSheet extends ConsumerStatefulWidget {
  const _TotpSetupSheet();

  @override
  ConsumerState<_TotpSetupSheet> createState() => _TotpSetupSheetState();
}

class _TotpSetupSheetState extends ConsumerState<_TotpSetupSheet> {
  final _controller = TextEditingController();
  TotpConfig? _config;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _check(String text) {
    setState(() {
      if (text.trim().isEmpty) {
        _config = null;
        _error = null;
        return;
      }
      try {
        _config = TotpConfig.parse(text);
        _error = null;
      } on FormatException catch (e) {
        _config = null;
        _error = e.message;
      }
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) showError(context, 'The clipboard is empty.');
      return;
    }
    _controller.text = text.trim();
    _check(_controller.text);
  }

  Future<void> _save() async {
    final config = _config;
    if (config == null) return;
    setState(() => _saving = true);
    // The code secret sits next to the saved password, so the phone itself
    // must be locked to the owner: turn on the app lock first where the
    // device has one (it asks for the fingerprint or PIN).
    final lock = ref.read(appLockProvider);
    if (lock.supported && !lock.enabled && !await ref.read(appLockProvider.notifier).setEnabled(true)) {
      if (!mounted) return;
      setState(() => _saving = false);
      showError(context, 'Automatic codes need the app lock. Confirm with your fingerprint or PIN to turn it on.');
      return;
    }
    await ref.read(secureStorageProvider).saveTotp(config.toUri());
    // The secret key shouldn't linger on the clipboard (some keyboards and
    // cloud clipboards keep or sync it).
    await Clipboard.setData(const ClipboardData(text: ''));
    ref.invalidate(totpConfigProvider);
    if (!mounted) return;
    Navigator.pop(context);
    showSuccess(context, 'Automatic codes are on.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: scheme.primaryContainer,
                child: Text('$n', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  children: [
                    Text('Set up automatic codes', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    step(
                        1,
                        'On a computer, open mysignins.microsoft.com → Security info → Add sign-in method → '
                        'Authenticator app.'),
                    step(2, 'Choose "I want to use a different authenticator app", then Next.'),
                    step(
                        3,
                        'Click "Can\'t scan image?" and type the secret key below. Don\'t send it to yourself '
                        'by email or chat: anyone who has it can make your codes.'),
                    step(4, 'Type the code shown below into the Microsoft page to finish adding it.'),
                    step(5, 'Set "Authenticator app or hardware token – code" as your default sign-in method.'),
                    if (ref.watch(appLockProvider).supported) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Saving turns on the app lock, so only you can open reSIT and its codes.',
                        style: muted,
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controller,
                      onChanged: _check,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Secret key or otpauth:// link',
                        errorText: _error,
                        suffixIcon: IconButton(
                          tooltip: 'Paste',
                          icon: const Icon(Icons.content_paste),
                          onPressed: _paste,
                        ),
                      ),
                    ),
                    if (_config != null) ...[
                      const SizedBox(height: 16),
                      Text('Current code', style: muted),
                      LiveCode(config: _config!),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The secret is kept encrypted on this phone only. With it saved next to your password, '
                            'anyone using this unlocked phone can sign in as you.',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: BusyButton(
                  onPressed: _config == null ? null : _save,
                  busy: _saving,
                  icon: Icons.check,
                  label: 'Turn on automatic codes',
                  busyLabel: 'Saving…',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
