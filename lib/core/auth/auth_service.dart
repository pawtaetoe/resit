import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:resit/core/auth/totp.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';

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

/// The saved session is gone and getting a new one needs credentials + MFA.
class SessionExpiredException implements Exception {
  /// What the sign-in page looked like, to help work out why SSO failed.
  final String? detail;

  SessionExpiredException([this.detail]);

  @override
  String toString() => 'Session expired.'
      '${detail != null ? '\n\n$detail' : ''}';
}

/// One-line summary of an HTML page for debugging: title, forms with their
/// field names (no values), and the start of the visible text.
String describeHtmlPage(String body) {
  final doc = parser.parse(body);
  final title = doc.querySelector('title')?.text.trim() ?? '';
  final forms = doc.querySelectorAll('form').map((f) {
    final names = f.querySelectorAll('input').map((i) => i.attributes['name']).whereType<String>();
    return '[${f.attributes['action'] ?? ''} fields=${names.join(",")}]';
  }).join(' ');
  final text = (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return 'title="$title" forms=$forms text="${text.substring(0, text.length.clamp(0, 300))}"';
}

class MfaException implements Exception {
  final String message;
  MfaException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final SessionClient client;
  final SecureStorage storage;

  AuthService(this.client, this.storage);

  static const String base = "https://rbs.singaporetech.edu.sg";
  static const String callback = "$base/Account/LoginCallbak";
  static const String protected = "$base/SRB001/SRB001Page";

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
  Future<bool>? _resuming;

  /// Recent sign-in steps from every sign-in (Account, automatic, and other
  /// apps' single sign-on such as the timetable), shown in Account → Sign-in
  /// details for troubleshooting. Page structure and field names only, never
  /// the password.
  final signInLog = ValueNotifier<List<String>>(const []);

  void _record(String message) {
    final t = DateTime.now();
    final stamp = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    final next = [...signInLog.value, '$stamp $message'];
    signInLog.value = next.length > 300 ? next.sublist(next.length - 300) : next;
  }

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

  // ---------------------------------------------------------------------------
  // Interactive login (credentials + MFA)
  // ---------------------------------------------------------------------------

  /// Full ADFS sign-in. If ADFS asks for MFA, [onMfaChallenge] is called so the
  /// UI can tell the user to approve the request in Microsoft Authenticator,
  /// and this future stays pending until they do (or [mfaTimeout] passes).
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

    client.clearCookies();
    _cachedCsrfToken = null;
    _lastValidated = null;

    // 1. GET the protected page. This redirects to ADFS.
    log('--- ADFS Login Started ---');
    var response = await client.get(Uri.parse(protected));
    log('Step 1 (GET protected page): Status ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch protected page.');
    }

    // The response URL is now the ADFS login form URL.
    var adfsUrl = response.request?.url;
    if (adfsUrl == null) throw Exception('No redirect to ADFS login page.');

    // 2. POST credentials to ADFS. Kmsi asks ADFS for its persistent
    // "keep me signed in" SSO cookie, which lets us skip MFA on later logins.
    var loginResponse = await client.post(
      adfsUrl,
      body: {
        "UserName": "$username@sit.singaporetech.edu.sg",
        "Password": password,
        "AuthMethod": "FormAuthentication",
        "Kmsi": "true",
      },
    );
    log('Step 2 (POST credentials): Status ${loginResponse.statusCode}');
    if (loginResponse.statusCode != 200) {
      throw Exception('Failed to post credentials to ADFS. Body: ${loginResponse.body.substring(0, 100)}...');
    }

    var page = loginResponse.body;
    var pageUrl = loginResponse.request?.url ?? adfsUrl;
    var fields = _extractRelayFields(page);

    // 3. MFA: ADFS answers a correct password with a challenge page instead
    // of the relay form.
    if (fields == null && _isMfaPage(page)) {
      log('Step 3 (MFA): ADFS requires multi-factor authentication.');
      page = (await _completeMfa(
        pageUrl,
        page,
        mfaTimeout: mfaTimeout,
        log: log,
        onChallenge: onMfaChallenge,
      ))
          .page;
      fields = _extractRelayFields(page);
    }

    if (fields == null) {
      final error = _extractError(parser.parse(page));
      throw Exception(error ?? "No wresult found in ADFS reply. Check your Student ID and Password.");
    }

    // 4. Replay the ADFS relay form to the callback
    log('Step 4 (Replay form to callback): POSTing ${fields.keys.join(", ")}');
    final callbackResponse = await client.post(Uri.parse(callback), body: fields);
    log('Step 4 Result: Status ${callbackResponse.statusCode}, URL: ${callbackResponse.request?.url}');

    if (callbackResponse.statusCode != 200 && callbackResponse.statusCode != 302) {
      log('Warning: Unexpected status code from callback: ${callbackResponse.statusCode}');
    }

    final hasCookie = client.hasAuthCookie();
    log('Final Check: hasAuthCookie = $hasCookie');
    if (hasCookie) {
      _lastValidated = DateTime.now();
      await _persistSession();
    }
    _setActive(hasCookie);
    return hasCookie;
  }

  /// Walks the MFA pages until ADFS hands back the relay form. Returns the
  /// HTML of that final page and the URL it came from.
  Future<({String page, Uri url})> _completeMfa(
    Uri startUrl,
    String startPage, {
    required Duration mfaTimeout,
    required void Function(String) log,
    void Function(MfaChallenge)? onChallenge,
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
      final doc = parser.parse(page);
      final code = _findCodeForm(doc);
      final form = code?.form ?? _pickForm(doc);
      if (form == null) {
        throw MfaException('ADFS MFA page has no form to submit.');
      }

      final action = form.attributes['action'];
      final target = (action == null || action.isEmpty) ? url : url.resolve(action);
      // With a code secret saved, pick the verification-code method when
      // the page offers a choice.
      final fields = _formFields(form, preferCode: totp != null);
      final number = _extractMfaNumber(doc);
      final codeInput = code?.name;

      if (step == 1 || codeInput != null) log('MFA page: ${_describeMfaPage(doc, fields)}');

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
          await sleep(Duration(seconds: totp.secondsLeft(clock()) + 1));
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

        final resp = await client.post(target, body: fields);
        url = resp.request?.url ?? target;
        page = resp.body;
        if (_extractRelayForm(page, url) != null) {
          log('MFA verification code accepted.');
          return (page: page, url: url);
        }
        final nextDoc = parser.parse(page);
        if (nextDoc.querySelector('input[type="password"]') != null) {
          throw MfaException(_extractError(nextDoc) ?? 'ADFS rejected the sign-in and went back to the password page.');
        }
        final error = _extractError(nextDoc);
        // A rejected code usually re-shows the code box with an error; try
        // once more with a fresh code, otherwise report the error.
        if (error != null && _findCodeForm(nextDoc) == null) {
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
        log('MFA poll $step: POST ${target.path} fields=${fields.keys.join(", ")}'
            '${number != null ? " number=$number" : ""}');
      }
      final resp = await client.post(target, body: fields).timeout(
            remaining,
            onTimeout: () => throw MfaException('Timed out waiting for Microsoft Authenticator approval.'),
          );

      url = resp.request?.url ?? target;
      page = resp.body;

      if (_extractRelayForm(page, url) != null) {
        log('MFA approved after $step poll(s).');
        return (page: page, url: url);
      }

      final nextDoc = parser.parse(page);
      if (nextDoc.querySelector('input[type="password"]') != null) {
        throw MfaException(_extractError(nextDoc) ?? 'ADFS rejected the sign-in and went back to the password page.');
      }
      // Moved on to a code page: answer it straight away, no polling pause.
      if (_findCodeForm(nextDoc) != null) continue;
      final error = _extractError(nextDoc);
      if (error != null) throw MfaException(error);

      // Still waiting for approval on the phone: poll again shortly.
      await sleep(const Duration(seconds: 2));
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

  /// The form and box on an MFA page that want a one-time code, searching
  /// every form (the code box isn't always in the form [_pickForm] chooses).
  ({dom.Element form, String name})? _findCodeForm(dom.Document doc) {
    for (final form in doc.querySelectorAll('form')) {
      final name = _findCodeInput(form);
      if (name != null) return (form: form, name: name);
    }
    return null;
  }

  /// The name of the box in [form] that wants a one-time code, or null.
  /// Matched by name/id/autocomplete since ADFS adapters name it differently
  /// (e.g. VerificationCode, otc, Passcode), then by code-like hints (numeric
  /// keyboard, 6-8 character limit), and finally, on a form with exactly one
  /// visible text box and no password box, that box.
  String? _findCodeInput(dom.Element form) {
    final pattern = RegExp(r'code|otp|otc|token|verification|passcode|pin', caseSensitive: false);
    final visible = <dom.Element>[];
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();
      if (!const {'text', 'tel', 'number', 'password'}.contains(type)) continue;
      final hints = '${input.attributes['autocomplete'] ?? ''} $name ${input.attributes['id'] ?? ''} '
          '${input.attributes['placeholder'] ?? ''} ${input.attributes['aria-label'] ?? ''}';
      if (hints.contains('one-time-code') || pattern.hasMatch(hints)) return name;
      if (type != 'password') visible.add(input);
    }

    for (final input in visible) {
      final numeric = (input.attributes['inputmode'] ?? '').toLowerCase() == 'numeric' ||
          (input.attributes['type'] ?? '').toLowerCase() == 'tel' ||
          (input.attributes['type'] ?? '').toLowerCase() == 'number' ||
          (input.attributes['pattern'] ?? '').contains(r'\d');
      final maxLength = int.tryParse(input.attributes['maxlength'] ?? '');
      if (numeric || (maxLength != null && maxLength >= 6 && maxLength <= 8)) return input.attributes['name'];
    }

    final hasPassword = form.querySelector('input[type="password"]') != null;
    if (visible.length == 1 && !hasPassword) return visible.single.attributes['name'];
    return null;
  }

  /// Debug summary of an MFA page: field values (Context is only measured)
  /// and the inline script that drives the page.
  String _describeMfaPage(dom.Document doc, Map<String, String> fields) {
    final values = fields.entries
        .map((e) => e.key == 'Context' ? 'Context(len=${e.value.length})' : '${e.key}="${e.value}"')
        .join(' ');
    final scripts = doc
        .querySelectorAll('script')
        .map((s) => s.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((t) => t.isNotEmpty && RegExp(r'complete|submit|__EVENTTARGET', caseSensitive: false).hasMatch(t))
        .map((t) => t.substring(0, t.length.clamp(0, 700)))
        .take(2)
        .join(' || ');
    final inputs = doc
        .querySelectorAll('input')
        .where((i) => (i.attributes['type'] ?? 'text').toLowerCase() != 'hidden')
        .map((i) => '${i.attributes['name'] ?? i.attributes['id'] ?? '?'}(${i.attributes['type'] ?? 'text'}'
            '${i.attributes['autocomplete'] != null ? ',${i.attributes['autocomplete']}' : ''})')
        .join(' ');
    final choices = doc
        .querySelectorAll('a, button, label')
        .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((t) =>
            RegExp(r'another way|other|code|verification|authenticator|text|call', caseSensitive: false).hasMatch(t))
        .where((t) => t.length < 80)
        .take(6)
        .join(' / ');
    return 'fields: $values | inputs: $inputs | choices: $choices | script: $scripts';
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
  /// still alive) that is replayed once.
  Future<bool> _validateSession() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await client.get(Uri.parse(protected));
      final url = response.request?.url;
      debugLog('Session check: status ${response.statusCode}, URL: $url');

      if (response.statusCode >= 400) return false;

      if (url != null && url.host == Uri.parse(base).host) {
        final token = _extractCsrf(response.body);
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
      final fields = _extractRelayFields(response.body);
      if (fields == null) return false;

      debugLog('Session check: ADFS SSO still valid, replaying relay form.');
      await client.post(Uri.parse(callback), body: fields);
    }
    return false;
  }

  Future<void> _persistSession() async {
    try {
      await storage.saveSession(client.exportCookies());
    } catch (e) {
      debugLog('Could not persist session: $e');
    }
  }

  void _setActive(bool value) {
    if (value) {
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

    if (_active != value) {
      _active = value;
      onSessionChanged?.call(value);
    }
  }

  /// GET [url] on another ADFS-protected app (e.g. in4sit). If it bounces to
  /// ADFS and the ADFS SSO session is still alive, the sign-in form is replayed
  /// to that app and the GET retried. If ADFS asks for credentials instead, the
  /// saved credentials are submitted (with MFA via [onMfaChallenge]) and the
  /// result replayed. If that is not possible the ADFS page is returned as-is,
  /// so callers should check where they ended up.
  Future<http.Response> getWithSso(
    Uri url, {
    void Function(String message)? onLog,
    void Function(MfaChallenge challenge)? onMfaChallenge,
    Duration mfaTimeout = const Duration(minutes: 2),
  }) async {
    var response = await client.get(url);
    var replayed = false;
    var signedIn = false;

    for (var i = 0; i < 3; i++) {
      final landed = response.request?.url ?? url;
      var relay = _extractRelayForm(response.body, landed);

      if (relay == null && !signedIn && landed.host != url.host) {
        debugLog('SSO: no relay form on ${landed.host}${landed.path} (status ${response.statusCode}). '
            'Cookies sent there: ${client.cookieNamesFor(landed)}');
        _record('SSO to ${url.host}: landed on ${landed.host}${landed.path} without a relay form.');
        _record('SSO page: ${describeHtmlPage(response.body)}');

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
        );
      }
      if (relay == null) break;

      debugLog('SSO: replaying ADFS relay form to ${relay.action.host}${relay.action.path}');
      await client.post(relay.action, body: relay.fields);
      replayed = true;
      response = await client.get(url);
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
      if (!_isAdfsMfaPage(doc)) return null;
      log('ADFS asks for multi-factor authentication for this app.');
      final mfa = await _completeMfa(pageUrl, page, mfaTimeout: mfaTimeout, log: log, onChallenge: onMfaChallenge);
      return _extractRelayForm(mfa.page, mfa.url);
    }

    final creds = await storage.getCredentials();
    final username = creds['username'];
    final password = creds['password'];
    if (username == null || username.isEmpty || password == null || password.isEmpty) return null;

    log('SSO unavailable, signing in to ADFS with saved credentials...');
    final action = form.attributes['action'];
    final target = (action == null || action.isEmpty) ? pageUrl : pageUrl.resolve(action);
    final fields = _formFields(form)
      ..addAll({
        "UserName": "$username@sit.singaporetech.edu.sg",
        "Password": password,
        "AuthMethod": "FormAuthentication",
        "Kmsi": "true",
      });

    final resp = await client.post(target, body: fields);
    log('ADFS sign-in: Status ${resp.statusCode}');
    var url = resp.request?.url ?? target;
    var body = resp.body;

    var relay = _extractRelayForm(body, url);
    if (relay == null && _isMfaPage(body)) {
      log('ADFS requires multi-factor authentication.');
      final mfa = await _completeMfa(url, body, mfaTimeout: mfaTimeout, log: log, onChallenge: onMfaChallenge);
      relay = _extractRelayForm(mfa.page, mfa.url);
    }
    if (relay == null) {
      throw Exception(_extractError(parser.parse(body)) ?? 'ADFS sign-in failed. Check your credentials in Settings.');
    }
    return relay;
  }

  ({Uri action, Map<String, String> fields})? _extractRelayForm(String body, Uri pageUrl) {
    final doc = parser.parse(body);
    for (final form in doc.querySelectorAll('form')) {
      final fields = <String, String>{};
      for (final input in form.querySelectorAll('input')) {
        final name = input.attributes['name'];
        if (name != null && name.isNotEmpty) fields[name] = input.attributes['value'] ?? '';
      }
      final keys = fields.keys.map((k) => k.toLowerCase());
      if (keys.contains('wresult') || keys.contains('samlresponse')) {
        final action = form.attributes['action'];
        return (
          action: (action == null || action.isEmpty) ? pageUrl : pageUrl.resolve(action),
          fields: fields,
        );
      }
    }
    return null;
  }

  Future<void> logout() async {
    client.clearCookies();
    _cachedCsrfToken = null;
    _lastValidated = null;
    await storage.clearSession();
    _setActive(false);
  }

  void dispose() {
    signInLog.dispose();
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<String?> getCsrfToken() async {
    final fresh = _lastValidated != null && DateTime.now().difference(_lastValidated!) < _tokenTtl;
    if (_cachedCsrfToken != null && fresh) return _cachedCsrfToken;

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

  // ---------------------------------------------------------------------------
  // HTML helpers
  // ---------------------------------------------------------------------------

  String? _extractCsrf(String body) {
    final doc = parser.parse(body);
    final input = doc.querySelector('input[name="__RequestVerificationToken"]');
    final token = input?.attributes['value'];
    if (token != null && token.isNotEmpty) return token;

    // Some apps expose it as a meta tag instead
    final meta = doc.querySelector('meta[name="csrf-token"], meta[name="__RequestVerificationToken"]');
    final metaToken = meta?.attributes['content'];
    if (metaToken != null && metaToken.isNotEmpty) return metaToken;
    return null;
  }

  Map<String, String>? _extractRelayFields(String body) {
    final document = parser.parse(body);
    final fields = <String, String>{};
    for (final input in document.querySelectorAll('input[type="hidden"]')) {
      final name = input.attributes['name'];
      final value = input.attributes['value'];
      if (name != null && value != null && ['wa', 'wresult', 'wctx'].contains(name.toLowerCase())) {
        fields[name] = value;
      }
    }
    return fields.containsKey('wresult') ? fields : null;
  }

  /// An ADFS MFA page: no password box, and a form carrying ADFS's
  /// AuthMethod/Context fields. Stricter than [_isMfaPage], which only runs
  /// right after a password was submitted.
  bool _isAdfsMfaPage(dom.Document doc) {
    if (doc.querySelector('input[type="password"]') != null) return false;
    return doc.querySelector('form input[name="AuthMethod"], form input[name="Context"]') != null;
  }

  /// A page that is not the relay form, has no password box (so it is not
  /// the login form re-rendered after a bad password) but does have a form.
  bool _isMfaPage(String body) {
    final doc = parser.parse(body);
    if (doc.querySelector('input[type="password"]') != null) return false;
    return _pickForm(doc) != null;
  }

  dom.Element? _pickForm(dom.Document doc) {
    final forms = doc.querySelectorAll('form');
    if (forms.isEmpty) return null;
    return forms.firstWhere(
      (f) => f.querySelector('input[name="AuthMethod"], input[name="Context"]') != null,
      orElse: () => forms.first,
    );
  }

  /// Collects what a browser would submit for [form]: hidden/text inputs,
  /// checked boxes/radios, the Authenticator-ish radio if none is checked, and
  /// the first named submit button.
  Map<String, String> _formFields(dom.Element form, {bool preferCode = false}) {
    final fields = <String, String>{};
    final radios = <String, List<dom.Element>>{};
    String? submitName;
    String? submitValue;

    for (final input in form.querySelectorAll('input, select, textarea')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = (input.attributes['type'] ?? 'text').toLowerCase();

      switch (type) {
        case 'submit':
        case 'button':
        case 'image':
          if (submitName == null) {
            submitName = name;
            submitValue = input.attributes['value'] ?? '';
          }
        case 'checkbox':
          if (input.attributes.containsKey('checked')) {
            fields[name] = input.attributes['value'] ?? 'on';
          }
        case 'radio':
          radios.putIfAbsent(name, () => []).add(input);
        default:
          fields[name] = input.attributes['value'] ?? '';
      }
    }

    radios.forEach((name, group) {
      final checked = group.where((r) => r.attributes.containsKey('checked'));
      final preferred = group.where((r) => RegExp(r'authenticator|notification|approve|push', caseSensitive: false)
          .hasMatch('${r.attributes['value']} ${r.parent?.text ?? ''}'));
      final codeOption = group.where((r) => RegExp(r'code|otp|otc|verification|token|passcode', caseSensitive: false)
          .hasMatch('${r.attributes['value']} ${r.parent?.text ?? ''}'));
      final pick = preferCode && codeOption.isNotEmpty
          ? codeOption.first
          : checked.isNotEmpty
              ? checked.first
              : preferred.isNotEmpty
                  ? preferred.first
                  : group.first;
      fields[name] = pick.attributes['value'] ?? '';
    });

    if (submitName != null) fields[submitName] = submitValue ?? '';
    return fields;
  }

  String? _extractMfaNumber(dom.Document doc) {
    // An element that is just the number (id/class mentions number or code)
    for (final el in doc.querySelectorAll('[id*="umber"], [class*="umber"], [id*="ode"], [class*="ode"]')) {
      final text = el.text.trim();
      if (RegExp(r'^\d{2,3}$').hasMatch(text)) return text;
    }
    // "... enter the number 57 ..." in the page text
    final text = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
    final match = RegExp(r'number\D{0,40}?(\d{2,3})\b', caseSensitive: false).firstMatch(text);
    return match?.group(1);
  }

  /// The error message an ADFS page shows, or null. ADFS fills its error box
  /// from a script after the page loads (`delayPopulate('errorText', "...")`),
  /// so that is read first; the "View details" link that sits in a box styled
  /// as an error is never taken for the message.
  String? _extractError(dom.Document doc) {
    final scripted =
        RegExp(r"""[dD]elayPopulate\(\s*['"]errorText['"]\s*,\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')""");
    for (final script in doc.querySelectorAll('script')) {
      for (final m in scripted.allMatches(script.text)) {
        final text = (m.group(1) ?? m.group(2) ?? '').replaceAll(r'\"', '"').replaceAll(r"\'", "'").trim();
        if (text.isNotEmpty) return text;
      }
    }

    for (final el in doc.querySelectorAll('#errorText, #error, .error, .error-text, [id*="rror"]')) {
      if (el.id == 'detailsDiv' || el.querySelector('#viewDetailsLink') != null) continue;
      final text = el.text.trim();
      if (text.isNotEmpty && text != 'View details') return text;
    }
    return null;
  }
}
