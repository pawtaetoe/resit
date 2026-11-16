import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts how often the cookie jar is written.
class _CountingStorage extends SecureStorage {
  int sessionWrites = 0;

  @override
  Future<void> saveSession(String cookiesJson) {
    sessionWrites++;
    return super.saveSession(cookiesJson);
  }
}

const _passwordPage = '<form method="post"><input name="UserName"><input type="password" name="Password"></form>';
const _adfs = 'https://fs.singaporetech.edu.sg/adfs/ls/?wa=wsignin1.0&wctx=secret-ctx';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'rbs_username': '2100000', 'rbs_password': 'hunter2'});
  });

  /// A server where the RBS page bounces to [landing], and every POST is
  /// recorded.
  AuthService service(String landing, List<http.Request> posts, {String page = _passwordPage}) {
    final mock = MockClient((request) async {
      if (request.method == 'POST') {
        posts.add(request);
        return http.Response('<html>nothing</html>', 200, request: request);
      }
      return http.Response(page, 200, request: http.Request('GET', Uri.parse(landing)));
    });
    return AuthService(SessionClient(mock), SecureStorage());
  }

  group('credentials only go to SIT ADFS', () {
    for (final landing in [
      'https://login.attacker.example/adfs/ls/',
      'http://fs.singaporetech.edu.sg/adfs/ls/',
      'https://fs.singaporetech.edu.sg.attacker.example/adfs/ls/',
      'https://rbs.singaporetech.edu.sg/Account/Login',
    ]) {
      test('login refuses to post the password to $landing', () async {
        final posts = <http.Request>[];
        final auth = service(landing, posts);
        await expectLater(auth.login('2100000', 'hunter2'), throwsA(isA<UntrustedHostException>()));
        auth.dispose();
        expect(posts, isEmpty);
      });
    }

    test('single sign-on refuses to post the saved password outside ADFS', () async {
      final posts = <http.Request>[];
      final auth = service('https://login.attacker.example/', posts);
      await expectLater(
        auth.getWithSso(Uri.parse('https://in4sit.singaporetech.edu.sg/psc/x')),
        throwsA(isA<UntrustedHostException>()),
      );
      auth.dispose();
      expect(posts, isEmpty);
    });

    test('MFA answers are not posted outside ADFS', () async {
      final posts = <http.Request>[];
      final mock = MockClient((request) async {
        if (request.method == 'POST' && request.bodyFields.containsKey('Password')) {
          posts.add(request);
          // The MFA form's action points somewhere else.
          return http.Response(
              '<form method="post" action="https://attacker.example/collect">'
              '<input type="hidden" name="AuthMethod" value="AzureMfaAuthentication">'
              '<input type="hidden" name="Context" value="ctx"></form>',
              200,
              request: request);
        }
        if (request.method == 'POST') posts.add(request);
        return http.Response(_passwordPage, 200, request: http.Request('GET', Uri.parse(_adfs)));
      });
      final auth = AuthService(SessionClient(mock), SecureStorage());
      await expectLater(auth.login('2100000', 'hunter2'), throwsA(isA<UntrustedHostException>()));
      auth.dispose();
      expect(posts.map((r) => r.url.host), ['fs.singaporetech.edu.sg']);
    });

    test('the sign-in token is only handed on to SIT apps over https', () async {
      final posts = <http.Request>[];
      const relay = '<form method="post" action="https://attacker.example/acs">'
          '<input type="hidden" name="SAMLResponse" value="token"></form>';
      final auth = service(_adfs, posts, page: relay);
      await expectLater(
        auth.getWithSso(Uri.parse('https://xsite.singaporetech.edu.sg/d2l/home')),
        throwsA(isA<UntrustedHostException>()),
      );
      auth.dispose();
      expect(posts, isEmpty);
    });
  });

  test('a failed credential post reports the status, not page text', () async {
    final mock = MockClient((request) async {
      if (request.method == 'POST') return http.Response('x', 500, request: request);
      return http.Response(_passwordPage, 200, request: http.Request('GET', Uri.parse(_adfs)));
    });
    final auth = AuthService(SessionClient(mock), SecureStorage());
    await expectLater(
      auth.login('2100000', 'hunter2'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', allOf(contains('500'), isNot(contains('x...'))))),
    );
    auth.dispose();
  });

  test('the sign-in log has no field values, query strings or the password', () async {
    var polls = 0;
    final mock = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(_passwordPage, 200, request: http.Request('GET', Uri.parse(_adfs)));
      }
      if (request.url.path == '/Account/LoginCallbak') {
        return http.Response('', 200,
            request: http.Request('GET', Uri.parse('https://rbs.singaporetech.edu.sg/home?code=secret-code')),
            headers: {'set-cookie': '.AspNet.Cookies=abc; Path=/'});
      }
      if (polls++ < 2) {
        return http.Response(
            '<form method="post" action="/adfs/ls/?client-request-id=secret-id">'
            '<input type="hidden" name="AuthMethod" value="AzureMfaAuthentication">'
            '<input type="hidden" name="Context" value="secret-context">'
            '<input type="hidden" name="UserName" value="2100000@sit.singaporetech.edu.sg">'
            '<script>function submitForm() { secretScript(); }</script></form>',
            200,
            request: request);
      }
      return http.Response(
          '<form action="https://rbs.singaporetech.edu.sg/Account/LoginCallbak">'
          '<input type="hidden" name="wresult" value="secret-token"></form>',
          200,
          request: request);
    });
    final auth = AuthService(SessionClient(mock), SecureStorage())..sleep = (_) async {};

    expect(await auth.login('2100000', 'hunter2'), isTrue);
    final log = auth.signInLog.value.join('\n');
    auth.dispose();

    expect(log, contains('Context'), reason: 'field names are still logged');
    for (final secret in ['hunter2', 'secret-context', 'secret-id', 'secret-code', 'secret-token', 'secretScript', '2100000@']) {
      expect(log, isNot(contains(secret)));
    }
  });

  group('session upkeep', () {
    const rbsPage = '<input name="__RequestVerificationToken" value="tok"/>';
    const jar = '[{"name":".AspNet.Cookies","value":"abc","domain":"rbs.singaporetech.edu.sg","path":"/","expires":null}]';

    test('checks at the same time share one request, and an unchanged jar is not rewritten', () async {
      FlutterSecureStorage.setMockInitialValues({'rbs_session_cookies': jar});
      var gets = 0;
      final mock = MockClient((request) async {
        gets++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(rbsPage, 200, request: request);
      });
      final storage = _CountingStorage();
      final auth = AuthService(SessionClient(mock), storage);

      expect(await auth.resumeSession(), isTrue);
      expect(gets, 1);
      expect(storage.sessionWrites, 0, reason: 'the restored jar is already saved');

      expect(await auth.getCsrfToken(), 'tok');
      expect(gets, 1, reason: 'the token from the check is still fresh');

      // No token yet: callers asking together share one check.
      final other = AuthService(SessionClient(mock), SecureStorage())..client.importCookies(jar);
      final tokens = await Future.wait([other.getCsrfToken(), other.getCsrfToken(), other.getCsrfToken()]);
      expect(tokens, ['tok', 'tok', 'tok']);
      expect(gets, 2);
      other.dispose();

      final checks = await Future.wait([auth.resumeSession(), auth.resumeSession()]);
      expect(checks, [true, true]);
      expect(gets, 3);
      expect(storage.sessionWrites, 0);
      auth.dispose();
    });

    test('signing out asks ADFS to end the session, but not for long', () async {
      FlutterSecureStorage.setMockInitialValues({'rbs_session_cookies': jar});
      Uri? signOut;
      final mock = MockClient((request) async {
        if (request.url.queryParameters['wa'] == 'wsignout1.0') {
          signOut = request.url;
          // ADFS doesn't answer.
          await Future<void>.delayed(const Duration(seconds: 30));
        }
        return http.Response(rbsPage, 200, request: request);
      });
      final auth = AuthService(SessionClient(mock), SecureStorage());
      expect(await auth.resumeSession(), isTrue);

      final watch = Stopwatch()..start();
      await auth.logout();
      watch.stop();
      auth.dispose();

      expect(signOut?.host, AuthService.adfsHost);
      expect(signOut?.scheme, 'https');
      expect(watch.elapsed, lessThan(AuthService.signOutTimeout + const Duration(seconds: 1)));
      expect(auth.isActive, isFalse);
      expect(auth.client.hasCookies, isFalse);
    });
  });
}
