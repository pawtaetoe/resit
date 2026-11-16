import 'package:resit/sites/adfs/sign_in_errors.dart';

/// The SIT hosts sign-in is allowed to talk to, and the checks that stop a
/// password, MFA answer or sign-in token going anywhere else.
abstract final class SitHosts {
  /// SIT's ADFS: the only host the saved student ID and password (and MFA
  /// answers) are ever sent to.
  static const String adfsHost = 'fs.singaporetech.edu.sg';

  /// ADFS sign-in tokens (the wresult / SAMLResponse relay forms) are only
  /// handed on to apps under this domain (RBS, in4SIT, xSiTe, ...). The
  /// token is issued by ADFS for one SIT app and is worthless to the others,
  /// so the whole SIT domain is allowed rather than a list of hosts that
  /// would break whenever SIT adds or moves an app; what this stops is a
  /// token going to a site outside SIT, or over plain http.
  static const String sitDomain = 'singaporetech.edu.sg';

  /// Whether [url] is SIT's ADFS over https.
  static bool isAdfs(Uri url) => url.scheme == 'https' && url.host.toLowerCase() == adfsHost;

  /// Whether [url] is an https address on SIT's own domain.
  static bool isSitHost(Uri url) {
    final host = url.host.toLowerCase();
    return url.scheme == 'https' && (host == sitDomain || host.endsWith('.$sitDomain'));
  }

  static void requireAdfs(Uri target, String what) {
    if (!isAdfs(target)) {
      throw UntrustedHostException('Stopped signing in: the sign-in page wanted your $what sent to '
          '${target.scheme}://${target.host}, which is not SIT\'s sign-in server ($adfsHost).');
    }
  }

  static void requireSitHost(Uri target) {
    if (!isSitHost(target)) {
      throw UntrustedHostException('Stopped signing in: the sign-in page wanted to pass your sign-in on to '
          '${target.scheme}://${target.host}, which is not an SIT (https://*.$sitDomain) address.');
    }
  }
}
