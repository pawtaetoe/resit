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

  /// A session confirmed this recently isn't re-checked when the app comes
  /// back to the foreground.
  static const recheckAfter = Duration(minutes: 2);

  SessionController(this._auth, this._storage) : super(const SessionState());

  /// Makes sure there's a working session, signing in again if needed.
  /// With [force], skips the check and signs in afresh (for when another
  /// app's single sign-on failed even though the session looked fine).
  /// Returns whether the user ends up signed in. Never throws.
  Future<bool> ensureSignedIn({bool force = false}) {
    return _running ??= _ensure(force: force).whenComplete(() => _running = null);
  }

  /// Signs in with newly entered credentials (from Account).
  Future<bool> signInWith(String username, String password) async {
    await _running;
    await _storage.saveCredentials(username, password);
    await _storage.setSignedOut(false);
    return ensureSignedIn(force: true);
  }

  /// Signs out and stops automatic sign-in until the user signs in again.
  Future<void> signOut({bool forgetDetails = false}) async {
    await _running;
    // Flag first: logging out triggers the "session dropped" listener, which
    // must see that this was on purpose.
    await _storage.setSignedOut(true);
    await _auth.logout();
    if (forgetDetails) {
      await _storage.clearCredentials();
      await _storage.clearTotp();
    }
    _lastConfirmed = null;
    state = const SessionState(phase: SessionPhase.signedOut);
  }

  Future<bool> _ensure({required bool force}) async {
    final recent = _lastConfirmed != null && DateTime.now().difference(_lastConfirmed!) < recheckAfter;
    if (!force && recent && _auth.isActive) return true;

    final log = <String>[];
    void addLog(String line) {
      log.add(line);
      if (mounted) state = state.copyWith(log: List.of(log), error: state.error);
    }

    state = SessionState(phase: SessionPhase.checking, log: log);

    try {
      if (!force && await _auth.resumeSession()) {
        return _done(true, log);
      }
      if (await _storage.isSignedOut()) {
        state = SessionState(phase: SessionPhase.signedOut, log: log);
        return false;
      }
      final creds = await _storage.getCredentials();
      final username = creds['username'];
      final password = creds['password'];
      if (username == null || username.isEmpty || password == null || password.isEmpty) {
        state = SessionState(phase: SessionPhase.signedOut, log: log);
        return false;
      }

      state = SessionState(phase: SessionPhase.signingIn, log: log);
      addLog(force ? 'Signing in afresh...' : 'Saved session has expired, signing in again...');
      final ok = await _auth.login(
        username,
        password,
        onLog: addLog,
        onMfaChallenge: (challenge) {
          if (mounted) state = state.copyWith(challenge: challenge, log: List.of(log));
        },
      );
      if (!ok) {
        state = SessionState(
          phase: SessionPhase.failed,
          error: "Couldn't sign in. Check your student ID and password in Account.",
          log: log,
        );
        return false;
      }
      return _done(true, log);
    } catch (e) {
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
