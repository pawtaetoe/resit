import 'package:html/parser.dart' as parser;
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/adfs/adfs_pages.dart';
import 'package:resit/sites/adfs/sign_in_errors.dart';
import 'package:resit/sites/adfs/sit_hosts.dart';
import 'package:resit/sites/adfs/totp.dart';

/// What the user has to do on their phone to finish an MFA sign-in.
class MfaChallenge {
  /// The number to tap/enter in Microsoft Authenticator (number matching),
  /// when the ADFS page shows one.
  final String? number;
  final String message;

  /// True when the app is answering the challenge itself with a
  /// verification code, so there's nothing to do on the phone.
  final bool automatic;

  const MfaChallenge({this.number, required this.message, this.automatic = false});
}

/// SIT's multi-factor step after the password: waits for a Microsoft
/// Authenticator approval (number matching included), or answers a
/// verification-code page itself with the saved code secret.
class MfaFlow {
  final SessionClient client;
  final SecureStorage storage;

  /// Time source and pause, replaceable to fast-forward through tests.
  final DateTime Function() clock;
  final Future<void> Function(Duration) sleep;

  MfaFlow(this.client, this.storage, {required this.clock, required this.sleep});

  /// Walks the MFA pages until ADFS hands back the relay form. Returns the
  /// HTML of that final page and the URL it came from.
  Future<({String page, Uri url})> complete(
    Uri startUrl,
    String startPage, {
    required Duration mfaTimeout,
    required void Function(String) log,
    void Function(MfaChallenge)? onChallenge,
    required CancelScope cancel,
  }) async {
    final deadline = clock().add(mfaTimeout);
    var url = startUrl;
    var page = startPage;
    String? announcedNumber;
    var announcedApproval = false;
    final totp = await _loadTotp(log);
    var codesSent = 0;
    String? codeError;
    String? lastCode;

    for (var step = 1;; step++) {
      cancel.check();
      final doc = parser.parse(page);
      final code = findCodeForm(doc);
      final form = code?.form ?? pickForm(doc);
      if (form == null) {
        throw MfaException('ADFS MFA page has no form to submit.');
      }

      final action = form.attributes['action'];
      final target = (action == null || action.isEmpty) ? url : url.resolve(action);
      // MFA forms carry the user name and the sign-in context: ADFS only.
      SitHosts.requireAdfs(target, 'sign-in verification');
      // With a code secret saved, pick the verification-code method when
      // the page offers a choice.
      final fields = formFields(form, preferCode: totp != null);
      final number = extractMfaNumber(doc);
      final codeInput = code?.name;

      if (step == 1 || codeInput != null) log('MFA page: ${describeMfaPage(doc, fields)}');

      // Verification-code page: answer it ourselves instead of waiting for
      // a push approval.
      if (codeInput != null) {
        if (totp == null) {
          throw MfaException('Sign-in is asking for a verification code. Set up automatic codes in '
              'Account, or change your default sign-in method back to app notifications.');
        }
        if (codesSent >= 2) {
          throw MfaException("The verification code wasn't accepted${codeError != null ? ' ($codeError)' : ''}. "
              "Check the code secret in Account and that this phone's clock is set automatically.");
        }
        // A code about to expire may be stale by the time it arrives, and a
        // code can't be used twice, so a retry waits for the next one.
        if (totp.secondsLeft(clock()) < 3 || totp.codeAt(clock()) == lastCode) {
          await cancel.guard(sleep(Duration(seconds: totp.secondsLeft(clock()) + 1)));
        }
        onChallenge?.call(const MfaChallenge(
          message: 'Entering your verification code automatically…',
          automatic: true,
        ));
        lastCode = totp.codeAt(clock());
        fields[codeInput] = lastCode;
        codesSent++;
        log('MFA: submitting verification code (attempt $codesSent) to ${target.path} '
            'as "$codeInput", other fields=${fields.keys.where((k) => k != codeInput).join(", ")}');

        final resp = await cancel.guard(client.post(target, body: fields));
        url = resp.request?.url ?? target;
        page = resp.body;
        if (extractRelayForm(page, url) != null) {
          log('MFA verification code accepted.');
          return (page: page, url: url);
        }
        final nextDoc = parser.parse(page);
        if (nextDoc.querySelector('input[type="password"]') != null) {
          throw MfaException(extractError(nextDoc) ?? 'ADFS rejected the sign-in and went back to the password page.');
        }
        final error = extractError(nextDoc);
        // A rejected code usually re-shows the code box with an error; try
        // once more with a fresh code, otherwise report the error.
        if (error != null && findCodeForm(nextDoc) == null) {
          throw MfaException(error);
        }
        if (error != null) {
          codeError = error;
          log('MFA: code rejected: $error');
        }
        continue;
      }

      if (number != null) {
        if (number != announcedNumber) {
          announcedNumber = number;
          onChallenge?.call(MfaChallenge(
            number: number,
            message: 'Open Microsoft Authenticator and enter the number $number to approve the sign-in.',
          ));
        }
      } else if (totp != null && step <= 2) {
        // With automatic codes on, a page without a number or code box is
        // usually a step on the way to the code page: don't ask the user to
        // approve anything yet.
        if (step == 1) {
          onChallenge?.call(const MfaChallenge(message: 'Verifying your sign-in…', automatic: true));
        }
      } else if (!announcedApproval) {
        announcedApproval = true;
        onChallenge?.call(const MfaChallenge(message: 'Open Microsoft Authenticator and approve the sign-in request.'));
      }

      final remaining = deadline.difference(clock());
      if (remaining <= Duration.zero) {
        throw MfaException('Timed out waiting for Microsoft Authenticator approval.');
      }

      // Submitting the challenge page either completes the sign-in (once the
      // user has approved on their phone) or just re-serves the same page, so
      // keep polling until the deadline.
      if (step <= 2 || step % 10 == 0) {
        log('MFA poll $step: POST ${target.path} fields=${fields.keys.join(", ")}');
      }
      // ADFS may hold this request open until the phone approves, so it
      // gets the rest of the MFA deadline rather than the client's default.
      final resp = await cancel.guard(
          client.withTimeout(remaining + const Duration(seconds: 5), () => client.post(target, body: fields)).timeout(
                remaining,
                onTimeout: () => throw MfaException('Timed out waiting for Microsoft Authenticator approval.'),
              ));

      url = resp.request?.url ?? target;
      page = resp.body;

      if (extractRelayForm(page, url) != null) {
        log('MFA approved after $step poll(s).');
        return (page: page, url: url);
      }

      final nextDoc = parser.parse(page);
      if (nextDoc.querySelector('input[type="password"]') != null) {
        throw MfaException(extractError(nextDoc) ?? 'ADFS rejected the sign-in and went back to the password page.');
      }
      // Moved on to a code page: answer it straight away, no polling pause.
      if (findCodeForm(nextDoc) != null) continue;
      final error = extractError(nextDoc);
      if (error != null) throw MfaException(error);

      // Still waiting for approval on the phone: poll again shortly.
      await cancel.guard(sleep(const Duration(seconds: 2)));
    }
  }

  Future<TotpConfig?> _loadTotp(void Function(String) log) async {
    try {
      final saved = await storage.getTotp();
      if (saved == null || saved.isEmpty) return null;
      return TotpConfig.parse(saved);
    } catch (e) {
      log('Saved verification code secret is unreadable: $e');
      return null;
    }
  }
}
