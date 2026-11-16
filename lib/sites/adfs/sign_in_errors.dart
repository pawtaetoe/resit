import 'dart:async';

/// The saved session is gone and getting a new one needs credentials + MFA.
class SessionExpiredException implements Exception {
  /// What the sign-in page looked like, to help work out why SSO failed.
  final String? detail;

  SessionExpiredException([this.detail]);

  @override
  String toString() => 'Session expired.'
      '${detail != null ? '\n\n$detail' : ''}';
}

class MfaException implements Exception {
  final String message;
  MfaException(this.message);

  @override
  String toString() => message;
}

/// The sign-in was stopped on purpose ([AuthService.cancelSignIn]); not an
/// error to show the user.
class SignInCancelledException implements Exception {
  @override
  String toString() => 'Sign-in cancelled.';
}

/// SIT turned the password down. The saved password is then not sent again
/// automatically until the user enters it afresh: repeating a wrong
/// password would lock the SIT account.
class CredentialsRejectedException implements Exception {
  /// What SIT's sign-in page said, if anything.
  final String? reason;
  const CredentialsRejectedException([this.reason]);

  @override
  String toString() => 'SIT did not accept your password${reason == null ? '' : ' ($reason)'}. '
      'If you changed it, enter the new one in Account.';
}

/// A sign-in step was about to send credentials or a sign-in token
/// somewhere other than SIT's own servers over https, and was stopped.
class UntrustedHostException implements Exception {
  final String message;
  UntrustedHostException(this.message);

  @override
  String toString() => message;
}

/// Lets AuthService.cancelSignIn stop sign-ins that are in progress.
class CancelScope {
  final _signal = Completer<void>();

  bool get isCancelled => _signal.isCompleted;

  void cancel() {
    if (!_signal.isCompleted) _signal.complete();
  }

  void check() {
    if (isCancelled) throw SignInCancelledException();
  }

  /// [future], or a [SignInCancelledException] as soon as this is cancelled.
  Future<T> guard<T>(Future<T> future) async {
    check();
    final result = await Future.any<T>([
      future,
      _signal.future.then<T>((_) => throw SignInCancelledException()),
    ]);
    check();
    return result;
  }
}
