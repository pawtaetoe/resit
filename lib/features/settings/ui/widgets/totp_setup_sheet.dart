import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/adfs/totp.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/settings/ui/widgets/live_code.dart';

/// Opens the steps to set up automatic codes, with a field for the secret.
Future<void> showTotpSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const TotpSetupSheet(),
  );
}

/// How to add reSIT as an authenticator app at Microsoft, the secret key
/// field, and the code it makes, so the user can check it before saving.
class TotpSetupSheet extends ConsumerStatefulWidget {
  const TotpSetupSheet({super.key});

  @override
  ConsumerState<TotpSetupSheet> createState() => _TotpSetupSheetState();
}

class _TotpSetupSheetState extends ConsumerState<TotpSetupSheet> {
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
