import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/settings/settings_providers.dart';
import 'package:resit/features/settings/ui/totp_section.dart';
import 'package:resit/features/settings/ui/widgets/account_status_banner.dart';
import 'package:resit/features/settings/ui/widgets/security_options.dart';
import 'package:resit/features/settings/ui/widgets/sign_in_form.dart';
import 'package:resit/features/settings/ui/widgets/sign_in_log_panel.dart';

/// Account tab: the first sign-in, the saved login, sign out, and automatic
/// verification codes. After the first sign-in the app signs itself back in
/// whenever the session expires, so there's no "sign in again" here.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  String? _savedUsername;

  /// A password is saved (or held for this run of the app). It is never put
  /// back into the form, where "show password" would reveal it to anyone
  /// holding the phone.
  bool _hasPassword = false;
  bool _remember = true;

  /// Showing the form to change the saved student ID or password.
  bool _editing = false;
  bool _busy = false;

  /// The technical sign-in log is shown after a failed sign-in, or on request.
  bool _showLog = false;

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
    final login = await ref.read(accountServiceProvider).savedLogin();
    if (!mounted) return;
    setState(() {
      _usernameController.text = login.username ?? '';
      _passwordController.clear();
      _savedUsername = login.username;
      _hasPassword = login.hasPassword;
      _remember = login.remembersPassword;
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // A blank password keeps the saved one.
    final ok = await ref.read(accountServiceProvider).signIn(_usernameController.text, _passwordController.text);
    await _loadCredentials();
    if (!mounted) return;
    if (ok) {
      setState(() => _editing = false);
      showSuccess(context, "You're signed in. The app will keep you signed in from now on.");
    }
  }

  Future<void> _signOut() async {
    // One tap per outcome instead of a checkbox plus a button.
    final choice = await showChoiceSheet<String>(
      context,
      icon: Icons.logout,
      title: 'Sign out?',
      message: "The app won't sign you back in automatically until you sign in here again. "
          'Your saved results and timetable are removed from this device.',
      choices: const [
        SheetChoice('keep', 'Sign out', icon: Icons.logout, primary: true),
        SheetChoice('forget', 'Sign out and forget my saved details', icon: Icons.delete_outline, danger: true),
        SheetChoice('stay', 'Stay signed in'),
      ],
    );
    if (choice == null || choice == 'stay') return;
    final forget = choice == 'forget';

    await ref.read(accountServiceProvider).signOut(forgetDetails: forget);
    if (forget) {
      _usernameController.clear();
      _passwordController.clear();
    }
    await _loadCredentials();
    if (!mounted) return;
    showSuccess(context, forget ? 'Signed out and saved details removed.' : 'Signed out.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final signedIn = ref.watch(authStateProvider);
    final session = ref.watch(sessionControllerProvider);
    _busy = session.busy;
    final showForm = !signedIn || _editing;
    final challenge = session.phase == SessionPhase.signingIn ? session.challenge : null;

    return Scaffold(
      // While signing in for the first time (or changing the saved login) the
      // main action stays pinned above the tabs, within thumb reach.
      bottomNavigationBar: showForm || (_busy && challenge != null)
          ? ThumbBar(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: BusyButton(
                      onPressed: _signIn,
                      busy: _busy,
                      icon: Icons.login,
                      label: _editing ? 'Save and sign in' : 'Sign in',
                      busyLabel: challenge != null && !challenge.automatic ? 'Waiting for approval…' : 'Signing in…',
                    ),
                  ),
                  // A sign-in can wait up to 2 minutes for approval: let it be stopped.
                  if (_busy) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => ref.read(sessionControllerProvider.notifier).cancelSignIn(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.page, Space.section, Space.page, 32),
              children: [
                // Same header as Home and Services.
                Text('Account', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: Space.page),
                AccountStatusBanner(
                  signedIn: signedIn,
                  phase: session.phase,
                  savedUsername: _savedUsername,
                  remember: _remember,
                  editing: _editing,
                  busy: _busy,
                  onChange: () => setState(() => _editing = true),
                ),
                const SizedBox(height: Space.section),
                if (challenge != null) ...[
                  MfaCard(challenge: challenge),
                  const SizedBox(height: Space.section),
                ],
                if (signedIn && !_editing) ...[
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
                if (showForm) ...[
                  Text(_editing ? 'Change saved login' : 'Sign in', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _editing
                        ? 'Enter your new student ID or password. The app signs in with it straight away.'
                        : 'Use your SIT student ID and password. The first time, approve the sign-in in '
                            'Microsoft Authenticator within 2 minutes; after that the app signs you back in '
                            'automatically whenever the session expires.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 16),
                  SignInForm(
                    formKey: _formKey,
                    usernameController: _usernameController,
                    passwordController: _passwordController,
                    busy: _busy,
                    editing: _editing,
                    hasPassword: _hasPassword,
                    showPassword: _showPassword,
                    onToggleShowPassword: () => setState(() => _showPassword = !_showPassword),
                    onSubmit: _signIn,
                  ),
                  if (_editing)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() => _editing = false);
                                _loadCredentials();
                              },
                        child: const Text('Cancel'),
                      ),
                    ),
                ],
                if (session.phase == SessionPhase.failed && session.error != null) ...[
                  const SizedBox(height: Space.page),
                  StatusBanner(
                    tone: Tone.danger,
                    icon: Icons.error_outline,
                    title: "Couldn't sign you in",
                    message: session.error!,
                  ),
                ],
                const SizedBox(height: Space.section),
                SecurityOptions(
                  remember: _remember,
                  busy: _busy,
                  onRememberChanged: (on) async {
                    await ref.read(accountServiceProvider).setRemembersPassword(on);
                    await _loadCredentials();
                  },
                ),
                // Automatic codes only make sense once there's a login to use them with.
                if (signedIn || _savedUsername != null) ...[
                  const SizedBox(height: Space.section),
                  const TotpSection(),
                ],
                const SizedBox(height: Space.page),
                Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _remember
                            ? 'Your password is stored only on this device, encrypted by the system keychain, '
                                'and is only ever sent to SIT.'
                            : 'Your password is not stored. It is only ever sent to SIT.',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
                // Every sign-in's steps, for troubleshooting.
                SignInTroubleshooting(
                  showLog: _showLog || session.phase == SessionPhase.failed,
                  onShowLog: () => setState(() => _showLog = true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
