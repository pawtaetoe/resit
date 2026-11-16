import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/section_label.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/settings/presentation/totp_section.dart';

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
    final storage = ref.read(secureStorageProvider);
    final creds = await storage.getCredentials();
    final remember = await storage.remembersPassword();
    if (!mounted) return;
    setState(() {
      _usernameController.text = creds['username'] ?? '';
      _passwordController.clear();
      _savedUsername = creds['username'];
      _hasPassword = (creds['password'] ?? '').isNotEmpty;
      _remember = remember;
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // Left blank: keep the saved password (e.g. only the ID changed).
    // Passwords can legitimately start or end with spaces, so no trim.
    final password = _passwordController.text.isNotEmpty
        ? _passwordController.text
        : (await ref.read(secureStorageProvider).getCredentials())['password'] ?? '';
    final ok = await ref.read(sessionControllerProvider.notifier).signInWith(
          _usernameController.text.trim(),
          password,
        );
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

    await ref.read(sessionControllerProvider.notifier).signOut(forgetDetails: forget);
    // Grades and the timetable don't stay on the device after any sign-out.
    await ref.read(academicRecordServiceProvider).clear();
    ref.invalidate(savedAcademicRecordProvider);
    ref.invalidate(academicRecordProvider);
    await ref.read(upcomingClassesServiceProvider).clear();
    await ref.read(timetableWeekStoreProvider).clear();
    ref.invalidate(savedUpcomingClassesProvider);
    ref.invalidate(upcomingClassesProvider);
    ref.read(lmsServiceProvider).clearCache();
    ref.invalidate(lmsProgressProvider);
    ref.invalidate(lmsContentsProvider);
    for (final p in [
      lmsAnnouncementsProvider,
      lmsAssignmentsProvider,
      lmsQuizzesProvider,
      lmsGradesProvider,
      lmsGroupsProvider,
      lmsCourseDueProvider,
    ]) {
      ref.invalidate(p);
    }
    if (forget) {
      ref.invalidate(totpConfigProvider);
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
                    OutlinedButton(
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
                _statusBanner(signedIn, session.phase),
                const SizedBox(height: Space.section),
                if (challenge != null) ...[
                  MfaCard(challenge: challenge),
                  const SizedBox(height: Space.section),
                ],
                if (signedIn && !_editing) ...[
                  OutlinedButton.icon(
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
                  _buildForm(),
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
                _securityOptions(),
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
                // Every sign-in's steps (including the timetable's), for
                // troubleshooting.
                // Shown after a failed sign-in, or behind "Having trouble?".
                ValueListenableBuilder<List<String>>(
                  valueListenable: ref.watch(authServiceProvider).signInLog,
                  builder: (context, log, _) {
                    if (log.isEmpty) return const SizedBox.shrink();
                    if (!_showLog && session.phase != SessionPhase.failed) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _showLog = true),
                          child: const Text('Having trouble signing in?'),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: Space.page),
                      child: _LogPanel(log: log.join('\n')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The app lock and whether the password is kept on the device.
  Widget _securityOptions() {
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
                    if (!ok && mounted) showError(context, "Couldn't confirm it's you, so the app lock wasn't changed.");
                  },
                ),
              if (lock.supported) const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.password),
                title: const Text('Remember my password'),
                subtitle: Text(_remember
                    ? 'Kept on this device, encrypted, so the app signs you back in whenever SIT times you out.'
                    : 'Not kept. After the app is closed you enter it again (SIT may also ask for MFA).'),
                value: _remember,
                onChanged: _busy
                    ? null
                    : (on) async {
                        await ref.read(secureStorageProvider).setRemembersPassword(on);
                        await _loadCredentials();
                      },
              ),
            ],
          ),
        ),
        if (lock.supported && !lock.enabled && _remember)
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

  /// Whether you're signed in, and as whom. When signed in, "Change" edits
  /// the saved login.
  Widget _statusBanner(bool signedIn, SessionPhase phase) {
    if (signedIn) {
      return StatusBanner(
        tone: Tone.success,
        icon: Icons.verified_user_outlined,
        title: _savedUsername != null ? 'Signed in as $_savedUsername' : 'Signed in',
        message: _remember
            ? 'The app signs you back in automatically when your session expires.'
            : 'Signed in until you close the app.',
        action: _editing
            ? null
            : TextButton(onPressed: _busy ? null : () => setState(() => _editing = true), child: const Text('Change')),
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
                helperText: _editing && _hasPassword ? 'Leave blank to keep your saved password' : null,
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
              validator: (v) => (v == null || v.isEmpty) && !(_editing && _hasPassword) ? 'Enter your password' : null,
            ),
          ],
        ),
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
