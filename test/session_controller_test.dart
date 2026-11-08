import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fake RBS + ADFS: the session is valid only after a password login.
class _FakeServer {
  bool sessionValid = false;
  int logins = 0;
  int signOuts = 0;

  /// The password ADFS accepts.
  String password = 'pw';

  /// ADFS asks for push approval after the password, and never gets it.
  bool mfaPending = false;

  /// The next N password posts stall until the client gives up.
  int stalls = 0;

  static const _mfaPage = '<form method="post" action="/adfs/ls/?client-request-id=1">'
      '<input type="hidden" name="AuthMethod" value="AzureMfaAuthentication"/>'
      '<input type="hidden" name="Context" value="ctx"/></form>';

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/SRB001/SRB001Page') {
      return sessionValid
          ? http.Response('<input name="__RequestVerificationToken" value="tok"/>', 200, request: request)
          // Expired: bounced to the ADFS password page.
          : http.Response('<form><input type="password" name="Password"></form>', 200,
              request: http.Request('GET', Uri.parse('https://fs.singaporetech.edu.sg/adfs/ls/')));
    }
    if (request.method == 'GET' && request.url.queryParameters['wa'] == 'wsignout1.0') {
      signOuts++;
      return http.Response('signed out', 200, request: request);
    }
    if (request.method == 'POST' && request.bodyFields.containsKey('Password')) {
      logins++;
      if (stalls > 0) {
        stalls--;
        throw TimeoutException('No response from fs.singaporetech.edu.sg in time.');
      }
      if (request.bodyFields['Password'] != password) {
        return http.Response(
            '<form><input type="password" name="Password"></form>'
            '<div id="errorText">Incorrect user ID or password.</div>',
            200,
            request: request);
      }
      if (mfaPending) return http.Response(_mfaPage, 200, request: request);
      return http.Response(
        '<form action="https://rbs.singaporetech.edu.sg/Account/LoginCallbak">'
        '<input type="hidden" name="wresult" value="t"/></form>',
        200,
        request: request,
      );
    }
    if (request.method == 'POST' && request.bodyFields.containsKey('Context')) {
      // Still waiting for the phone.
      return http.Response(_mfaPage, 200, request: request);
    }
    if (path == '/Account/LoginCallbak') {
      sessionValid = true;
      return http.Response('', 200, request: request, headers: {'set-cookie': '.AspNet.Cookies=abc; Path=/'});
    }
    return http.Response('not found', 404, request: request);
  });
}

void main() {
  late _FakeServer server;
  late AuthService auth;
  late SessionController controller;
  late SecureStorage storage;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    server = _FakeServer();
  });

  tearDown(() {
    controller.dispose();
    auth.dispose();
  });

  void build(Map<String, String> stored) {
    FlutterSecureStorage.setMockInitialValues(Map.of(stored));
    storage = SecureStorage();
    auth = AuthService(SessionClient(server.client), storage)
      // MFA polls without the 2 s pause.
      ..sleep = ((_) => Future<void>.delayed(const Duration(milliseconds: 5)));
    controller = SessionController(auth, storage);
  }

  const creds = {'rbs_username': '2100000', 'rbs_password': 'pw'};

  test('signs back in by itself when the saved session has expired', () async {
    build(creds);
    expect(await controller.ensureSignedIn(), isTrue);
    expect(server.logins, 1);
    expect(controller.state.phase, SessionPhase.signedIn);
    expect(auth.isActive, isTrue);
  });

  test('a recently confirmed session is not re-checked', () async {
    build(creds);
    await controller.ensureSignedIn();
    expect(await controller.ensureSignedIn(), isTrue);
    expect(server.logins, 1);
  });

  test('concurrent calls share one sign-in', () async {
    build(creds);
    final results = await Future.wait([controller.ensureSignedIn(), controller.ensureSignedIn()]);
    expect(results, [true, true]);
    expect(server.logins, 1);
  });

  test('a sign-in step that times out is retried once by itself', () async {
    build(creds);
    server.stalls = 1;
    expect(await controller.ensureSignedIn(), isTrue);
    expect(server.logins, 2);
    expect(controller.state.phase, SessionPhase.signedIn);
  });

  test('two timeouts in a row are reported, not retried forever', () async {
    build(creds);
    server.stalls = 2;
    expect(await controller.ensureSignedIn(), isFalse);
    expect(server.logins, 2);
    expect(controller.state.phase, SessionPhase.failed);
    expect(controller.state.error, contains('too long'));
  });

  test('sign-in requests may take longer than ordinary page loads', () {
    build(creds);
    expect(AuthService.signInStepTimeout, greaterThan(SessionClient.defaultTimeout));
  });

  test('does nothing without saved credentials', () async {
    build({});
    expect(await controller.ensureSignedIn(), isFalse);
    expect(server.logins, 0);
    expect(controller.state.phase, SessionPhase.signedOut);
  });

  test('after signing out on purpose, it stays signed out', () async {
    build(creds);
    await controller.ensureSignedIn();
    await controller.signOut();
    expect(await controller.ensureSignedIn(), isFalse);
    expect(server.logins, 1);
    expect(controller.state.phase, SessionPhase.signedOut);
  });

  test('signing out also ends the ADFS single sign-on session', () async {
    build(creds);
    await controller.ensureSignedIn();
    await controller.signOut();
    expect(server.signOuts, 1);
    expect(auth.isActive, isFalse);
  });

  test('signing in again from Account turns automatic sign-in back on', () async {
    build(creds);
    await controller.signOut();
    server.sessionValid = false;
    expect(await controller.signInWith('2100000', 'pw'), isTrue);
    expect(controller.state.phase, SessionPhase.signedIn);
    expect(await storage.isSignedOut(), isFalse);
  });

  test('new details are saved only once they have worked', () async {
    build(creds);
    await controller.signOut();

    // A typo: not saved, so it isn't retried on every resume.
    expect(await controller.signInWith('2100000', 'typo'), isFalse);
    expect(controller.state.phase, SessionPhase.failed);
    expect((await storage.getCredentials())['password'], 'pw');
    expect(await storage.isSignedOut(), isTrue, reason: 'still signed out on purpose');

    server.password = 'new-pw';
    expect(await controller.signInWith('2100001', 'new-pw'), isTrue);
    final saved = await storage.getCredentials();
    expect(saved['username'], '2100001');
    expect(saved['password'], 'new-pw');
  });

  test('a sign-in waiting for MFA approval can be cancelled', () async {
    build(creds);
    server.mfaPending = true;

    final result = controller.ensureSignedIn();
    // Wait until it is asking for approval on the phone.
    while (controller.state.challenge == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.state.phase, SessionPhase.signingIn);

    await controller.cancelSignIn();

    expect(await result, isFalse);
    expect(controller.state.phase, SessionPhase.signedOut);
    expect(controller.state.error, isNull, reason: 'cancelling is not an error');
    expect(controller.state.busy, isFalse);
    expect(auth.isActive, isFalse);
    // Doesn't start the MFA prompt again by itself.
    expect(await storage.isSignedOut(), isTrue);
    expect(await controller.ensureSignedIn(), isFalse);
    expect(server.logins, 1);
  });

  test('signing out cancels a sign-in that is waiting for MFA', () async {
    build(creds);
    server.mfaPending = true;

    final result = controller.ensureSignedIn();
    while (controller.state.challenge == null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await controller.signOut().timeout(const Duration(seconds: 5));

    expect(await result, isFalse);
    expect(controller.state.phase, SessionPhase.signedOut);
  });

  test('the keep-alive pauses while the app is in the background', () async {
    build(creds);
    await controller.ensureSignedIn();
    expect(auth.keepAliveRunning, isTrue);

    controller.appLifecycleChanged(AppLifecycleState.hidden);
    expect(auth.keepAliveRunning, isFalse);
    controller.appLifecycleChanged(AppLifecycleState.paused);
    expect(auth.keepAliveRunning, isFalse);

    controller.appLifecycleChanged(AppLifecycleState.resumed);
    expect(auth.keepAliveRunning, isTrue);

    // Signed out while paused: it stays off after coming back.
    controller.appLifecycleChanged(AppLifecycleState.hidden);
    await controller.signOut();
    controller.appLifecycleChanged(AppLifecycleState.resumed);
    expect(auth.keepAliveRunning, isFalse);
  });
}
