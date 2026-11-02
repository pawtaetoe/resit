import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';

/// Account tab: sign in with the SIT (ADFS) account, see the session status,
/// sign out.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  bool _hasSavedCredentials = false;
  MfaChallenge? _mfaChallenge;
  String? _error;
  final _log = StringBuffer();

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    final creds = await ref.read(secureStorageProvider).getCredentials();
    if (!mounted) return;
    setState(() {
      _usernameController.text = creds['username'] ?? '';
      _passwordController.text = creds['password'] ?? '';
      _hasSavedCredentials = creds['username'] != null;
    });
  }

  void _addLog(String line) {
    if (mounted) setState(() => _log.writeln(line));
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
      _mfaChallenge = null;
      _log.clear();
    });

    final username = _usernameController.text.trim();
    // Passwords can legitimately start or end with spaces, so no trim.
    final password = _passwordController.text;

    try {
      final storage = ref.read(secureStorageProvider);
      final previous = await storage.getCredentials();
      final unchanged = previous['username'] == username && previous['password'] == password;
      await storage.saveCredentials(username, password);
      _addLog('Credentials saved to secure storage.');
      _hasSavedCredentials = true;

      final authService = ref.read(authServiceProvider);

      // Same credentials and a live session: no need to bother Authenticator.
      var success = false;
      if (unchanged) {
        _addLog('Checking the existing session...');
        success = await authService.resumeSession();
        _addLog(success ? 'Existing session is still valid, no MFA needed.' : 'Saved session has expired.');
      }

      if (!success) {
        _addLog('Starting ADFS sign-in...');
        success = await authService.login(
          username,
          password,
          onLog: _addLog,
          onMfaChallenge: (challenge) {
            if (!mounted) return;
            setState(() => _mfaChallenge = challenge);
            _addLog('Waiting for Microsoft Authenticator approval...');
          },
        );
      }

      ref.read(authStateProvider.notifier).state = success;
      _addLog(success ? 'Signed in. Session saved.' : 'Sign-in failed.');

      if (!mounted) return;
      setState(() {
        _busy = false;
        _mfaChallenge = null;
        if (!success) _error = 'Sign-in failed. Check your student ID and password.';
      });
      if (success) showSuccess(context, "You're signed in.");
    } catch (e) {
      _addLog('ERROR: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _mfaChallenge = null;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _signOut() async {
    var forget = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.logout),
          title: const Text('Sign out?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("You'll need to approve the next sign-in in Microsoft Authenticator."),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: forget,
                onChanged: (v) => setDialogState(() => forget = v ?? false),
                title: const Text('Also remove my saved student ID and password'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay signed in')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await ref.read(authServiceProvider).logout();
    ref.read(authStateProvider.notifier).state = false;
    if (forget) {
      await ref.read(secureStorageProvider).clearCredentials();
      _usernameController.clear();
      _passwordController.clear();
      _hasSavedCredentials = false;
    }
    if (!mounted) return;
    setState(_log.clear);
    showSuccess(context, forget ? 'Signed out and saved details removed.' : 'Signed out.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = ref.watch(authStateProvider);
    final restoring = ref.watch(sessionRestoringProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _StatusCard(
                  signedIn: signedIn,
                  busy: _busy || restoring,
                  username: _hasSavedCredentials ? _usernameController.text : null,
                ),
                const SizedBox(height: 24),
                if (_mfaChallenge != null) ...[
                  MfaCard(challenge: _mfaChallenge!),
                  const SizedBox(height: 24),
                ],
                Text(signedIn ? 'Sign in again' : 'Sign in', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Use your SIT student ID and password. You approve the sign-in once in '
                  'Microsoft Authenticator; after that the app keeps you signed in until the session expires.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                _buildForm(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBox(message: _error!),
                ],
                const SizedBox(height: 16),
                BusyButton(
                  onPressed: _signIn,
                  busy: _busy,
                  icon: Icons.login,
                  label: signedIn ? 'Sign in again' : 'Sign in',
                  busyLabel: _mfaChallenge != null ? 'Waiting for approval…' : 'Signing in…',
                ),
                if (signedIn) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your password is stored only on this device, encrypted by the system keychain.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _LogPanel(log: _log.toString()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _usernameController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'e.g. 2100000',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your student ID' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _signIn(),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool signedIn;
  final bool busy;
  final String? username;

  const _StatusCard({required this.signedIn, required this.busy, this.username});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Tone tone, IconData icon, String title, String detail) = signedIn
        ? (Tone.success, Icons.verified_user_outlined, 'Signed in', username != null ? 'Student ID $username' : 'Session active')
        : busy
            ? (Tone.info, Icons.sync, 'Connecting…', 'Checking your SIT session')
            : (Tone.warning, Icons.person_off_outlined, 'Not signed in', 'Sign in below to use bookings and timetable');
    final (bg, fg) = tone.colors(theme.colorScheme);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: fg.withValues(alpha: 0.12),
              child: Icon(icon, color: fg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(color: fg)),
                  Text(detail, style: TextStyle(color: fg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = Tone.danger.colors(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}

/// Technical sign-in log, collapsed by default: useful for troubleshooting,
/// noise for everyone else.
class _LogPanel extends StatelessWidget {
  final String log;
  const _LogPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: const Text('Sign-in details'),
        subtitle: const Text('For troubleshooting'),
        shape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
