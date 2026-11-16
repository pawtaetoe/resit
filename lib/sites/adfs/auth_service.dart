import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/adfs/adfs_pages.dart';
import 'package:resit/sites/adfs/mfa_flow.dart';
import 'package:resit/sites/adfs/sign_in_errors.dart';
import 'package:resit/sites/adfs/sign_in_log.dart';
import 'package:resit/sites/adfs/sit_hosts.dart';

// The rest of SIT sign-in lives next to this file; importing this one brings
// in the types callers need.
export 'package:resit/sites/adfs/mfa_flow.dart' show MfaChallenge;
export 'package:resit/sites/adfs/sign_in_errors.dart'
    show
        SessionExpiredException,
        MfaException,
        SignInCancelledException,
        CredentialsRejectedException,
        UntrustedHostException;
export 'package:resit/sites/adfs/sign_in_log.dart' show loggableUrl, describeHtmlPage, SignInLog;
export 'package:resit/sites/adfs/sit_hosts.dart' show SitHosts;

class AuthService {
  final SessionClient client;
  final SecureStorage storage;

  AuthService(this.client, this.storage);

  static const String base = "https://rbs.singaporetech.edu.sg";
  static const String callback = "$base/Account/LoginCallbak";
  static const String protected = "$base/SRB001/SRB001Page";

  /// How long signing out waits for ADFS to end the single sign-on session.
  static const Duration signOutTimeout = Duration(seconds: 3);

  /// How often the session is pinged while the app is open. Hitting the
  /// protected page keeps the RBS cookie's sliding expiry alive and renews
  /// the ADFS SSO session without another MFA prompt.
  static const Duration keepAliveInterval = Duration(minutes: 10);

  /// A cached CSRF token is trusted for this long before the session is
  /// re-validated.
  static const Duration _tokenTtl = Duration(minutes: 5);

  String? _cachedCsrfToken;
  DateTime? _lastValidated;
  bool _restored = false;
  bool _active = false;
  Timer? _keepAliveTimer;
  bool _keepAlivePaused = false;
  Future<bool>? _resuming;
  Future<bool>? _validating;
  Future<String?>? _fetchingToken;

  /// The cookie jar as last written to storage, so unchanged jars aren't
  /// rewritten on every check.
  String? _persistedJar;

  CancelScope _cancel = CancelScope();

  /// Stops every sign-in in progress (password + MFA, here or for another
  /// app's single sign-on) at its next step: they end with a
  /// [SignInCancelledException]. Sign-ins started afterwards are unaffected.
  void cancelSignIn() {
    _cancel.cancel();
    _cancel = CancelScope();
  }

  /// See [SignInLog].
  final signInLog = SignInLog();

  void _record(String message) => signInLog.record(message);

  /// Time source and pause used by the MFA steps; tests replace them to
  /// fast-forward through code periods.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;
  @visibleForTesting
  Future<void> Function(Duration) sleep = (d) => Future<void>.delayed(d);

  /// Adds a line to [signInLog] from elsewhere in the app (e.g. what the room
  /// list contained), for troubleshooting.
  void note(String message) {
    debugLog(message);
    _record(message);
  }

  /// Called whenever the session flips between signed-in and signed-out.
  void Function(bool active)? onSessionChanged;

  bool get isActive => _active;

  late final MfaFlow _mfa = MfaFlow(client, storage, clock: () => clock(), sleep: (d) => sleep(d));

  // ---------------------------------------------------------------------------
  // Interactive login (credentials + MFA)
  // ---------------------------------------------------------------------------

  /// Full ADFS sign-in. If ADFS asks for MFA, [onMfaChallenge] is called so the
  /// UI can tell the user to approve the request in Microsoft Authenticator,
  /// and this future stays pending until they do (or [mfaTimeout] passes).
  /// How long one request may take during sign-in. SIT's sign-in server
  /// can take well over the client's 30 s default when it's busy.
  static const signInStepTimeout = Duration(seconds: 90);

  Future<bool> login(
    String username,
    String password, {
    void Function(String message)? onLog,
    void Function(MfaChallenge challenge)? onMfaChallenge,
    Duration mfaTimeout = const Duration(minutes: 2),
  }) async {
    void log(String message) {
      debugLog(message);
      _record(message);
      onLog?.call(message);
    }

    final cancel = _cancel;
    client.clearCookies();
    _cachedCsrfToken = null;
    _lastValidated = null;

    try {
      // SIT's sign-in server can be slow when busy: sign-in steps get longer
      // than the client's default per request (the MFA wait has its own).
      return await client.withTimeout(
          signInStepTimeout,
          () => _login(username, password,
              cancel: cancel, log: log, onMfaChallenge: onMfaChallenge, mfaTimeout: mfaTimeout));
    } on SignInCancelledException {
      log('Sign-in cancelled.');
      client.clearCookies();
      _cachedCsrfToken = null;
      _lastValidated = null;
      _setActive(false);
      rethrow;
    }
  }

  Future<bool> _login(
    String username,
    String password, {
    required CancelScope cancel,
    required void Function(String message) log,
    void Function(MfaChallenge challenge)? onMfaChallenge,
    required Duration mfaTimeout,
  }) async {
    // 1. GET the protected page. This redirects to ADFS.
    log('--- ADFS Login Started ---');
    var response = await cancel.guard(client.get(Uri.parse(protected)));
    log('Step 1 (GET protected page): Status ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch protected page.');
    }

    // The response URL is now the ADFS login form URL.
    var adfsUrl = response.request?.url;
    if (adfsUrl == null) throw Exception('No redirect to ADFS login page.');
    // Never hand the password to wherever a redirect happened to land.
    SitHosts.requireAdfs(adfsUrl, 'student ID and password');

    // 2. POST credentials to ADFS. Kmsi asks ADFS for its persistent
    // "keep me signed in" SSO cookie, which lets us skip MFA on later logins.
    var loginResponse = await cancel.guard(client.post(
      adfsUrl,
      body: {
        "UserName": "$username@sit.singaporetech.edu.sg",
        "Password": password,
        "AuthMethod": "FormAuthentication",
        "Kmsi": "true",
      },
    ));
    log('Step 2 (POST credentials): Status ${loginResponse.statusCode}');
    if (loginResponse.statusCode != 200) {
      throw Exception('Failed to post credentials to ADFS (status ${loginResponse.statusCode}).');
    }

    var page = loginResponse.body;
    var pageUrl = loginResponse.request?.url ?? adfsUrl;
    var fields = extractRelayFields(page);

    // 3. MFA: ADFS answers a correct password with a challenge page instead
    // of the relay form.
    if (fields == null && isMfaPage(page)) {
      log('Step 3 (MFA): ADFS requires multi-factor authentication.');
      page = (await _mfa.complete(
        pageUrl,
        page,
        mfaTimeout: mfaTimeout,
        log: log,
        onChallenge: onMfaChallenge,
        cancel: cancel,
      ))
          .page;
      fields = extractRelayFields(page);
    }

    if (fields == null) {
      final error = extractError(parser.parse(page));
      if (asksForPassword(page)) await _rejected(username, password, error);
      throw Exception(error ?? "No wresult found in ADFS reply. Check your Student ID and Password.");
    }

    // 4. Replay the ADFS relay form to the callback
    cancel.check();
    log('Step 4 (Replay form to callback): POSTing ${fields.keys.join(", ")}');
    final callbackResponse = await cancel.guard(client.post(Uri.parse(callback), body: fields));
    final landed = callbackResponse.request?.url;
    log('Step 4 Result: Status ${callbackResponse.statusCode}, URL: ${landed == null ? '?' : loggableUrl(landed)}');

    if (callbackResponse.statusCode != 200 && callbackResponse.statusCode != 302) {
      log('Warning: Unexpected status code from callback: ${callbackResponse.statusCode}');
    }

    final hasCookie = client.hasAuthCookie();
    log('Final Check: hasAuthCookie = $hasCookie');
    cancel.check();
    if (hasCookie) {
      _lastValidated = DateTime.now();
      await _persistSession();
    }
    _setActive(hasCookie);
    return hasCookie;
  }

  // ---------------------------------------------------------------------------
  // Session reuse and keep-alive
  // ---------------------------------------------------------------------------

  /// Brings the session back without asking for credentials or MFA: loads the
  /// saved cookies, and lets ADFS single sign-on mint a fresh RBS cookie if the
  /// RBS one has lapsed. Returns false if a full login (with MFA) is needed.
  /// Network errors are rethrown so a flaky connection never looks like a
  /// logged-out session.
  Future<bool> resumeSession() {
    return _resuming ??= _resumeSession().whenComplete(() => _resuming = null);
  }

  Future<bool> _resumeSession() async {
    if (!_restored) {
      _restored = true;
      final saved = await storage.getSession();
      if (saved != null && !client.hasCookies) {
        try {
          client.importCookies(saved);
          _persistedJar = saved;
        } catch (e) {
          debugLog('Could not restore saved session: $e');
        }
      }
    }

    if (!client.hasCookies) {
      _setActive(false);
      return false;
    }

    final valid = await _validateSession();
    if (valid) await _persistSession();
    _setActive(valid);
    return valid;
  }

  /// GETs the protected page. Valid if it renders (with a CSRF token) rather
  /// than bouncing to ADFS; if ADFS answers with a ready relay form (SSO is
  /// still alive) that is replayed once. Concurrent checks (keep-alive,
  /// resume, CSRF refresh) share one round trip.
  Future<bool> _validateSession() {
    return _validating ??= _doValidateSession().whenComplete(() => _validating = null);
  }

  Future<bool> _doValidateSession() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await client.get(Uri.parse(protected));
      final url = response.request?.url;
      debugLog('Session check: status ${response.statusCode}, URL: ${url == null ? '?' : loggableUrl(url)}');

      if (response.statusCode >= 400) return false;

      if (url != null && url.host == Uri.parse(base).host) {
        final token = extractCsrf(response.body);
        if (token != null) {
          _cachedCsrfToken = token;
          _lastValidated = DateTime.now();
          return true;
        }
        debugLog('CRITICAL: No CSRF token in HTML. First 800 chars:');
        debugLog(response.body.substring(0, response.body.length.clamp(0, 800)));
        return false;
      }

      // Landed on ADFS. Without a relay form we would need credentials + MFA.
      final fields = extractRelayFields(response.body);
      if (fields == null) return false;

      debugLog('Session check: ADFS SSO still valid, replaying relay form.');
      await client.post(Uri.parse(callback), body: fields);
    }
    return false;
  }

  /// Saves the cookie jar, unless it is exactly what was saved last time
  /// (most checks change nothing, and each write re-encrypts the whole jar).
  Future<void> _persistSession() async {
    try {
      final jar = client.exportCookies();
      if (jar == _persistedJar) return;
      await storage.saveSession(jar);
      _persistedJar = jar;
    } catch (e) {
      debugLog('Could not persist session: $e');
    }
  }

  /// Stops the keep-alive pings, e.g. while the app is in the background,
  /// so it doesn't wake the radio every 10 minutes for nothing.
  void pauseKeepAlive() {
    _keepAlivePaused = true;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// Restarts the keep-alive pings after [pauseKeepAlive] (if signed in).
  /// The app checks the session itself when it comes back, so this doesn't
  /// ping straight away.
  void resumeKeepAlive() {
    _keepAlivePaused = false;
    _updateKeepAlive();
  }

  @visibleForTesting
  bool get keepAliveRunning => _keepAliveTimer != null;

  void _updateKeepAlive() {
    if (_active && !_keepAlivePaused) {
      _keepAliveTimer ??= Timer.periodic(keepAliveInterval, (_) async {
        try {
          await resumeSession();
        } catch (_) {
          // Offline right now; try again on the next tick.
        }
      });
    } else {
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
    }
  }

  void _setActive(bool value) {
    final changed = _active != value;
    _active = value;
    _updateKeepAlive();

    if (changed) onSessionChanged?.call(value);
  }

  /// GET [url] on another ADFS-protected app (e.g. in4sit). If it bounces to
  /// ADFS and the ADFS SSO session is still alive, the sign-in form is replayed
  /// to that app and the GET retried. If ADFS asks for credentials instead, the
  /// saved credentials are submitted (with MFA via [onMfaChallenge]) and the
  /// result replayed. If that is not possible the ADFS page is returned as-is,
  /// so callers should check where they ended up.
  ///
  /// [thenGet] is fetched after signing in instead of [url], for apps whose
  /// sign-in starts at a different address than the page wanted (xSiTe signs
  /// in at its SAML start page, then serves the course list).
  Future<http.Response> getWithSso(
    Uri url, {
    Uri? thenGet,
    void Function(String message)? onLog,
    void Function(MfaChallenge challenge)? onMfaChallenge,
    Duration mfaTimeout = const Duration(minutes: 2),
  }) =>
      // Single sign-on runs through SIT's sign-in server too: same longer limit.
      client.withTimeout(
          signInStepTimeout,
          () =>
              _getWithSso(url, thenGet: thenGet, onLog: onLog, onMfaChallenge: onMfaChallenge, mfaTimeout: mfaTimeout));

  Future<http.Response> _getWithSso(
    Uri url, {
    Uri? thenGet,
    void Function(String message)? onLog,
    void Function(MfaChallenge challenge)? onMfaChallenge,
    required Duration mfaTimeout,
  }) async {
    final cancel = _cancel;
    var response = await client.get(url);
    var replayed = false;
    var signedIn = false;

    for (var i = 0; i < 3; i++) {
      final landed = response.request?.url ?? url;
      // Only SIT's sign-in server hands out sign-in tokens: a token-like form
      // on any other page is not replayed (it could sign the app in to
      // someone else's session).
      var relay = SitHosts.isAdfs(landed) ? extractRelayForm(response.body, landed) : null;

      if (relay == null && !signedIn && landed.host != url.host) {
        debugLog('SSO: no relay form on ${landed.host}${landed.path} (status ${response.statusCode}). '
            'Cookies sent there: ${client.cookieNamesFor(landed)}');
        _record('SSO to ${url.host}: landed on ${landed.host}${landed.path} without a relay form.');
        _record('SSO page: ${describeHtmlPage(response.body, includeText: false)}');

        signedIn = true;
        relay = await _signInAtAdfs(
          landed,
          response.body,
          log: (m) {
            debugLog(m);
            _record(m);
            onLog?.call(m);
          },
          onMfaChallenge: onMfaChallenge,
          mfaTimeout: mfaTimeout,
          cancel: cancel,
        );
      }
      if (relay == null) break;

      // The relay form carries a sign-in token: SIT apps over https only.
      SitHosts.requireSitHost(relay.action);
      debugLog('SSO: replaying ADFS relay form to ${relay.action.host}${relay.action.path}');
      await cancel.guard(client.post(relay.action, body: relay.fields));
      replayed = true;
      response = await client.get(thenGet ?? url);
    }
    if (replayed) await _persistSession();
    return response;
  }

  /// Submits the saved credentials to an ADFS login form (plus MFA) and
  /// returns the relay form ADFS answers with. If ADFS skips the password and
  /// goes straight to MFA (an app that asks for MFA again even though the
  /// ADFS session is alive), that MFA page is completed instead. Returns null
  /// if the page is neither, or there are no saved credentials.
  Future<({Uri action, Map<String, String> fields})?> _signInAtAdfs(
    Uri pageUrl,
    String page, {
    required void Function(String) log,
    void Function(MfaChallenge)? onMfaChallenge,
    required Duration mfaTimeout,
    required CancelScope cancel,
  }) async {
    final doc = parser.parse(page);
    dom.Element? form;
    for (final f in doc.querySelectorAll('form')) {
      if (f.querySelector('input[type="password"]') != null) {
        form = f;
        break;
      }
    }
    if (form == null) {
      if (!isAdfsMfaPage(doc)) return null;
      log('ADFS asks for multi-factor authentication for this app.');
      final mfa = await _mfa.complete(pageUrl, page,
          mfaTimeout: mfaTimeout, log: log, onChallenge: onMfaChallenge, cancel: cancel);
      return extractRelayForm(mfa.page, mfa.url);
    }

    final creds = await storage.getCredentials();
    final username = creds['username'];
    final password = creds['password'];
    if (username == null || username.isEmpty || password == null || password.isEmpty) return null;
    // SIT already turned this password down: sending it again could lock
    // the account. The user enters it afresh in Account.
    if (await storage.credentialsRejected()) {
      log('Saved password was rejected before; not sending it again.');
      throw const CredentialsRejectedException();
    }

    final action = form.attributes['action'];
    final target = (action == null || action.isEmpty) ? pageUrl : pageUrl.resolve(action);
    // Only ever give the saved password to SIT's ADFS, whatever page a
    // redirect landed on.
    SitHosts.requireAdfs(target, 'saved student ID and password');
    log('SSO unavailable, signing in to ADFS with saved credentials...');
    final fields = formFields(form)
      ..addAll({
        "UserName": "$username@sit.singaporetech.edu.sg",
        "Password": password,
        "AuthMethod": "FormAuthentication",
        "Kmsi": "true",
      });

    final resp = await cancel.guard(client.post(target, body: fields));
    log('ADFS sign-in: Status ${resp.statusCode}');
    var url = resp.request?.url ?? target;
    var body = resp.body;

    var relay = extractRelayForm(body, url);
    if (relay == null && isMfaPage(body)) {
      log('ADFS requires multi-factor authentication.');
      final mfa =
          await _mfa.complete(url, body, mfaTimeout: mfaTimeout, log: log, onChallenge: onMfaChallenge, cancel: cancel);
      relay = extractRelayForm(mfa.page, mfa.url);
    }
    if (relay == null) {
      final error = extractError(parser.parse(body));
      if (asksForPassword(body)) await _rejected(username, password, error);
      throw Exception(error ?? 'ADFS sign-in failed. Check your credentials in Settings.');
    }
    return relay;
  }

  /// Records that SIT turned down [password] if it is the saved one, so it
  /// is never sent again automatically, and stops with a clear message.
  Future<Never> _rejected(String username, String password, String? error) async {
    final saved = await storage.getCredentials();
    if (saved['username'] == username && saved['password'] == password) await storage.setCredentialsRejected();
    throw CredentialsRejectedException(error);
  }

  /// Signs out: asks ADFS to end its single sign-on session (so the
  /// "keep me signed in" cookie can't be used again even if it leaked),
  /// then forgets the cookies here. The ADFS call is best effort and gives
  /// up after [signOutTimeout], so signing out works offline too.
  Future<void> logout() async {
    if (client.hasCookies) {
      try {
        final signOut = Uri.https(SitHosts.adfsHost, '/adfs/ls/', {'wa': 'wsignout1.0'});
        await client.withTimeout(signOutTimeout, () => client.get(signOut)).timeout(signOutTimeout);
      } catch (e) {
        debugLog('ADFS sign-out failed (ignored): $e');
      }
    }
    client.clearCookies();
    // The troubleshooting log can name the account: not kept past sign-out.
    signInLog.clear();
    _cachedCsrfToken = null;
    _lastValidated = null;
    await storage.clearSession();
    _persistedJar = null;
    _setActive(false);
  }

  void dispose() {
    signInLog.dispose();
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  /// The RBS CSRF token, re-validating the session when the cached one is
  /// stale. Callers asking at the same time share one check.
  Future<String?> getCsrfToken() {
    final fresh = _lastValidated != null && DateTime.now().difference(_lastValidated!) < _tokenTtl;
    if (_cachedCsrfToken != null && fresh) return Future.value(_cachedCsrfToken);
    return _fetchingToken ??= _refreshCsrfToken().whenComplete(() => _fetchingToken = null);
  }

  Future<String?> _refreshCsrfToken() async {
    final valid = await _validateSession();
    if (valid) {
      await _persistSession();
      return _cachedCsrfToken;
    }

    // Session is gone and renewing it would need MFA.
    _cachedCsrfToken = null;
    _setActive(false);
    return null;
  }
}
