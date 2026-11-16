import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:resit/core/network/session_client.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/xsite/lms_unavailable_exception.dart';
import 'package:resit/sites/xsite/request_limiter.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';

/// GETs from xSiTe, signing in to it through SIT's ADFS when it answers with
/// its login page, and keeping a few requests out at once at most.
class XsiteClient {
  /// Starts xSiTe's SIT sign-in (SAML via ADFS).
  static final samlLogin = Uri.parse('$xsiteBase/d2l/lp/auth/saml/login?target=%2fd2l%2fhome');

  final AuthService auth;
  final RequestLimiter _limit;

  /// The xSiTe sign-in under way, shared by every request that finds xSiTe
  /// signed out meanwhile.
  Future<void>? _signingIn;

  /// xSiTe sign-ins finished so far, to tell whether one happened while a
  /// request was out.
  var _signIns = 0;

  /// When xSiTe last answered with data, i.e. was certainly signed in.
  DateTime? _lastOk;

  /// [maxInFlight] limited requests are out at once, at most.
  XsiteClient(this.auth, {required int maxInFlight}) : _limit = RequestLimiter(maxInFlight);

  SessionClient get _client => auth.client;

  /// GETs [url] as is, taking turns with the other limited requests.
  Future<http.Response> getLimited(Uri url) => _limit(() => _client.get(url));

  /// GETs an xSiTe API; if xSiTe isn't signed in yet (it answers with its
  /// login page instead of JSON), signs in through ADFS and asks again. When
  /// several requests find xSiTe signed out at once, one signs in and the
  /// others wait for it, then ask again. [limited] requests take turns
  /// within the client's `maxInFlight`.
  Future<String> getJson(Uri url, void Function(MfaChallenge)? onMfaChallenge, {bool limited = false}) async {
    Future<http.Response> get() => limited ? getLimited(url) : _client.get(url);
    String ok(String body) {
      _lastOk = DateTime.now();
      return body;
    }

    final signInsBefore = _signIns;
    var resp = await get();
    var body = resp.body;
    if (_isJson(resp.statusCode, resp.headers, body)) return ok(body);
    // Signed in a moment ago, so "forbidden" or "not found" is about this
    // tool (not used in the course, or closed to students), not the session.
    if (_refused(resp, url) && _lastOk != null && DateTime.now().difference(_lastOk!) < const Duration(minutes: 5)) {
      throw LmsUnavailableException(url.path);
    }

    final pending = _signingIn;
    if (pending != null || _signIns != signInsBefore) {
      // Someone else is signing in, or did while this was out: wait for
      // them, then ask again.
      await pending;
      resp = await get();
      body = resp.body;
      if (_isJson(resp.statusCode, resp.headers, body)) return ok(body);
    } else {
      debugLog('xSiTe: not signed in (status ${resp.statusCode}, at ${resp.request?.url.path}); signing in');
      // Waiters only need to know it's over; this request reports any error.
      final done = Completer<void>();
      _signingIn = done.future;
      try {
        resp = await auth.getWithSso(samlLogin, thenGet: url, onMfaChallenge: onMfaChallenge);
      } finally {
        _signingIn = null;
        _signIns++;
        done.complete();
      }
      body = resp.body;
      if (_isJson(resp.statusCode, resp.headers, body)) return ok(body);
    }
    // Still refused after signing in: the tool isn't available, not the session.
    if (_refused(resp, url)) throw LmsUnavailableException(url.path);

    final landed = resp.request?.url;
    throw SessionExpiredException(
        "xSiTe didn't sign in${landed == null ? '' : ' (ended on ${landed.host}${landed.path})'}.");
  }

  /// A 403/404 from the address asked for itself (not a sign-in page).
  static bool _refused(http.Response resp, Uri url) {
    final landed = resp.request?.url;
    return (resp.statusCode == 403 || resp.statusCode == 404) &&
        landed != null &&
        landed.host == url.host &&
        landed.path == url.path;
  }

  static bool _isJson(int status, Map<String, String> headers, String body) {
    if (status != 200) return false;
    final type = headers['content-type'] ?? '';
    final t = stripGuard(body);
    return type.contains('json') || t.startsWith('{') || t.startsWith('[');
  }
}
