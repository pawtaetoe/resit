import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/ui/feedback.dart';

enum SessionPhase {
  /// Nothing has been checked yet.
  idle,

  /// Checking whether the saved session is still valid.
  checking,

  /// Signing in with the saved credentials (may involve MFA).
  signingIn,
  signedIn,

  /// No saved credentials, or the user signed out on purpose.
  signedOut,

  /// Signing in was attempted and failed; see [SessionState.error].
  failed,
}

class SessionState {
  final SessionPhase phase;

  /// What MFA needs right now while [SessionPhase.signingIn], if anything.
  final MfaChallenge? challenge;
  final String? error;

  /// Technical log of the last sign-in, for troubleshooting in Account.
  final List<String> log;

  const SessionState({this.phase = SessionPhase.idle, this.challenge, this.error, this.log = const []});

  bool get busy => phase == SessionPhase.checking || phase == SessionPhase.signingIn;

  SessionState copyWith(
          {SessionPhase? phase,
          MfaChallenge? challenge,
          bool clearChallenge = false,
          String? error,
          List<String>? log}) =>
      SessionState(
        phase: phase ?? this.phase,
        challenge: clearChallenge ? null : (challenge ?? this.challenge),
        error: error,
        log: log ?? this.log,
      );
}

/// Keeps the user signed in without them asking: checks the saved session
/// and, if it has expired, signs in again with the saved student ID and
/// password (MFA by push approval or an automatic verification code). All
/// automatic and manual sign-ins go through here, so only one runs at once.
class SessionController extends StateNotifier<SessionState> {
  final AuthService _auth;
  final SecureStorage _storage;

  Future<bool>? _running;
  DateTime? _lastConfirmed;
  bool _cancelled = false;
  AppLifecycleListener? _lifecycle;

  /// A session confirmed this recently isn't re-checked when the app comes
  /// back to the foreground.
  static const recheckAfter = Duration(minutes: 2);

  /// Automatic sign-ins with the saved password allowed in an hour, well
  /// under the number of failures that locks an SIT account.
  static const maxAutoSignInsPerHour = 6;
  final List<DateTime> _autoSignIns = [];

  /// With [watchLifecycle] (the default), the session keep-alive is paused
  /// while the app is in the background and restarted when it comes back
  /// (needs the Flutter binding, which the app and widget tests have).
  SessionController(this._auth, this._storage, {bool watchLifecycle = true}) : super(const SessionState()) {
    if (watchLifecycle) {
      _lifecycle = AppLifecycleListener(onStateChange: appLifecycleChanged);
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Pauses the keep-alive while the app can't be seen, resumes it when it
  /// is in front again. Public so the app (or a test) can drive it directly.
  void appLifecycleChanged(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _auth.pauseKeepAlive();
      case AppLifecycleState.resumed:
        _auth.resumeKeepAlive();
      case AppLifecycleState.inactive:
        // Passing through (a dialog, the app switcher): leave it as it is.
        break;
    }
  }

  /// Makes sure there's a working session, signing in again if needed.
  /// With [force], skips the check and signs in afresh (for when another
  /// app's single sign-on failed even though the session looked fine).
  /// Returns whether the user ends up signed in. Never throws.
  Future<bool> ensureSignedIn({bool force = false}) {
    return _running ??= _ensure(force: force).whenComplete(() => _running = null);
  }

  /// Signs in with newly entered credentials (from Account). They are only
  /// saved once ADFS has accepted them, so a mistyped password isn't retried
  /// automatically on every resume (which could lock the account).
  Future<bool> signInWith(String username, String password) async {
    await _running;
    return _running ??= _ensure(force: true, entered: (username: username, password: password))
        .whenComplete(() => _running = null);
  }

  /// Stops a sign-in in progress (e.g. one waiting for approval in
  /// Microsoft Authenticator). It ends signed out, without an error, and the
  /// app doesn't sign itself back in until the user signs in again from
  /// Account (the saved details are kept). Does nothing when no sign-in is
  /// running.
  Future<void> cancelSignIn() async {
    final running = _running;
    if (running == null) return;
    _cancelled = true;
    // Flag first: the cancelled sign-in drops the session, and the "session
    // dropped" listener must see that this was on purpose.
    await _storage.setSignedOut(true);
    _auth.cancelSignIn();
    await running;
  }

  /// Signs out and stops automatic sign-in until the user signs in again.
  /// A sign-in still waiting (e.g. for MFA approval) is cancelled rather
  /// than waited for. ADFS is asked to end its session too (best effort, a
  /// few seconds at most).
  Future<void> signOut({bool forgetDetails = false}) async {
    // Flag first: logging out triggers the "session dropped" listener, which
    // must see that this was on purpose.
    await _storage.setSignedOut(true);
    final running = _running;
    if (running != null) {
      _cancelled = true;
      _auth.cancelSignIn();
      await running;
    }
    await _auth.logout();
    if (forgetDetails) {
      await _storage.clearCredentials();
      await _storage.clearTotp();
    }
    _lastConfirmed = null;
    state = const SessionState(phase: SessionPhase.signedOut);
  }

  /// [entered] are credentials just typed in Account: used instead of the
  /// saved ones, and saved (with automatic sign-in turned back on) only if
  /// they work.
  Future<bool> _ensure({required bool force, ({String username, String password})? entered}) async {
    _cancelled = false;
    final recent = _lastConfirmed != null && DateTime.now().difference(_lastConfirmed!) < recheckAfter;
    if (!force && recent && _auth.isActive) return true;

    final log = <String>[];
    void addLog(String line) {
      log.add(line);
      if (mounted) state = state.copyWith(log: List.of(log), error: state.error);
    }

    bool stopped() {
      if (!_cancelled) return false;
      log.add('Sign-in cancelled.');
      state = SessionState(phase: SessionPhase.signedOut, log: log);
      return true;
    }

    state = SessionState(phase: SessionPhase.checking, log: log);

    try {
      if (!force && await _auth.resumeSession()) {
        return _done(true, log);
      }
      if (stopped()) return false;
      if (entered == null && await _storage.isSignedOut()) {
        state = SessionState(phase: SessionPhase.signedOut, log: log);
        return false;
      }
      final creds = entered == null ? await _storage.getCredentials() : null;
      final username = entered?.username ?? creds?['username'];
      final password = entered?.password ?? creds?['password'];
      if (username == null || username.isEmpty || password == null || password.isEmpty) {
        state = SessionState(phase: SessionPhase.signedOut, log: log);
        return false;
      }
      if (entered == null) {
        // Never repeat a password SIT has turned down (that would lock the
        // account), and keep automatic sign-ins to a handful an hour.
        if (await _storage.credentialsRejected()) {
          state = SessionState(
              phase: SessionPhase.failed, error: const CredentialsRejectedException().toString(), log: log);
          return false;
        }
        final now = DateTime.now();
        _autoSignIns.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
        if (_autoSignIns.length >= maxAutoSignInsPerHour) {
          state = SessionState(
            phase: SessionPhase.failed,
            error: 'Automatic sign-in is paused for a while after several tries. Sign in from Account.',
            log: log,
          );
          return false;
        }
        _autoSignIns.add(now);
      }
      if (stopped()) return false;

      state = SessionState(phase: SessionPhase.signingIn, log: log);
      addLog(force ? 'Signing in afresh...' : 'Saved session has expired, signing in again...');
      Future<bool> attempt() => _auth.login(
            username,
            password,
            onLog: addLog,
            onMfaChallenge: (challenge) {
              if (mounted) state = state.copyWith(challenge: challenge, log: List.of(log));
            },
          );
      bool ok;
      try {
        ok = await attempt();
      } on TimeoutException catch (e) {
        // SIT's sign-in server sometimes stalls on one request; a fresh
        // attempt usually goes straight through. Retry once before failing.
        if (stopped()) return false;
        addLog('A sign-in step timed out ($e); trying once more...');
        ok = await attempt();
      }
      if (stopped()) return false;
      if (!ok) {
        state = SessionState(
          phase: SessionPhase.failed,
          error: "Couldn't sign in. Check your student ID and password in Account.",
          log: log,
        );
        return false;
      }
      if (entered != null) {
        await _storage.saveCredentials(entered.username, entered.password);
        await _storage.setSignedOut(false);
      }
      return _done(true, log);
    } on SignInCancelledException {
      // Also when cancelled straight through AuthService: quietly signed out.
      if (!stopped()) state = SessionState(phase: SessionPhase.signedOut, log: log);
      return false;
    } catch (e) {
      if (stopped()) return false;
      log.add('ERROR: $e');
      state = SessionState(phase: SessionPhase.failed, error: friendlyError(e), log: log);
      return false;
    }
  }

  bool _done(bool ok, List<String> log) {
    _lastConfirmed = DateTime.now();
    state = SessionState(phase: SessionPhase.signedIn, log: log);
    return ok;
  }
}
