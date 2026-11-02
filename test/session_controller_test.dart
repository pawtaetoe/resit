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

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/SRB001/SRB001Page') {
      return sessionValid
          ? http.Response('<input name="__RequestVerificationToken" value="tok"/>', 200, request: request)
          // Expired: bounced to the ADFS password page.
          : http.Response('<form><input type="password" name="Password"></form>', 200,
              request: http.Request('GET', Uri.parse('https://fs.example.edu/adfs/ls/')));
    }
    if (request.method == 'POST' && request.bodyFields.containsKey('Password')) {
      logins++;
      return http.Response(
        '<form action="https://rbs.singaporetech.edu.sg/Account/LoginCallbak">'
        '<input type="hidden" name="wresult" value="t"/></form>',
        200,
        request: request,
      );
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

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    server = _FakeServer();
  });

  tearDown(() => auth.dispose());

  void build(Map<String, String> stored) {
    FlutterSecureStorage.setMockInitialValues(Map.of(stored));
    auth = AuthService(SessionClient(server.client), SecureStorage());
    controller = SessionController(auth, SecureStorage());
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

  test('signing in again from Account turns automatic sign-in back on', () async {
    build(creds);
    await controller.signOut();
    server.sessionValid = false;
    expect(await controller.signInWith('2100000', 'pw'), isTrue);
    expect(controller.state.phase, SessionPhase.signedIn);
  });
}
