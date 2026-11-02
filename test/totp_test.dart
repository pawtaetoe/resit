import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/auth/totp.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// RFC 6238 test secrets: ASCII "1234567890" repeated to the key length.
const _sha1Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const _sha256Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';
const _sha512Secret =
    'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA';

DateTime _at(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

TotpConfig _rfc(String secret, String algorithm) =>
    TotpConfig.parse('otpauth://totp/Test?secret=$secret&algorithm=$algorithm&digits=8');

void main() {
  group('TotpConfig', () {
    test('matches the RFC 6238 test vectors', () {
      final vectors = {
        59: ['94287082', '46119246', '90693936'],
        1111111109: ['07081804', '68084774', '25091201'],
        1234567890: ['89005924', '91819424', '93441116'],
        20000000000: ['65353130', '77737706', '47863826'],
      };
      vectors.forEach((t, codes) {
        expect(_rfc(_sha1Secret, 'SHA1').codeAt(_at(t)), codes[0], reason: 'SHA1 at $t');
        expect(_rfc(_sha256Secret, 'SHA256').codeAt(_at(t)), codes[1], reason: 'SHA256 at $t');
        expect(_rfc(_sha512Secret, 'SHA512').codeAt(_at(t)), codes[2], reason: 'SHA512 at $t');
      });
    });

    test('reads issuer and account from an otpauth link', () {
      final c = TotpConfig.parse(
          'otpauth://totp/Microsoft:2100000%40sit.singaporetech.edu.sg?secret=jbswy3dpehpk3pxp&issuer=Microsoft');
      expect(c.issuer, 'Microsoft');
      expect(c.account, '2100000@sit.singaporetech.edu.sg');
      expect(c.digits, 6);
      expect(c.period, 30);
      expect(c.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('accepts a bare secret with spaces and lower case', () {
      final c = TotpConfig.parse('jbsw y3dp ehpk 3pxp');
      expect(c.secret, 'JBSWY3DPEHPK3PXP');
      expect(c.codeAt(DateTime.now()), hasLength(6));
    });

    test('round-trips through its stored link', () {
      final c = TotpConfig.parse('otpauth://totp/Microsoft:me?secret=JBSWY3DPEHPK3PXP&issuer=Microsoft');
      final again = TotpConfig.parse(c.toUri());
      expect(again.codeAt(_at(1234567890)), c.codeAt(_at(1234567890)));
      expect(again.issuer, 'Microsoft');
    });

    test('rejects input that is not a secret', () {
      expect(() => TotpConfig.parse(''), throwsFormatException);
      expect(() => TotpConfig.parse('not a secret!'), throwsFormatException);
      expect(() => TotpConfig.parse('otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP'), throwsFormatException);
      expect(() => TotpConfig.parse('otpauth://totp/x?issuer=y'), throwsFormatException);
    });

    test('secondsLeft counts down within the period', () {
      final c = TotpConfig.parse(_sha1Secret);
      expect(c.secondsLeft(_at(60)), 30);
      expect(c.secondsLeft(_at(89)), 1);
    });
  });

  group('Sign-in with a verification code page', () {
    const secret = 'JBSWY3DPEHPK3PXP';
    final config = TotpConfig.parse(secret);

    const codePage = '''
      <html><body>
        <form method="post" id="loginForm" action="/adfs/ls/?client-request-id=1">
          <input type="hidden" name="AuthMethod" value="AzureMfaAuthentication"/>
          <input type="hidden" name="Context" value="ctx"/>
          <input type="text" name="VerificationCode" autocomplete="off"/>
          <input type="submit" name="SignIn" value="Sign in"/>
        </form>
      </body></html>''';
    const relayPage = '''
      <html><body>
        <form method="POST" name="hiddenform" action="https://rbs.singaporetech.edu.sg/Account/LoginCallbak">
          <input type="hidden" name="wa" value="wsignin1.0"/>
          <input type="hidden" name="wresult" value="token"/>
        </form>
      </body></html>''';

    late List<String?> codesSeen;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      codesSeen = [];
    });

    Future<AuthService> service(
        {String? totp, bool acceptCode = true, String page = codePage, String field = 'VerificationCode'}) async {
      FlutterSecureStorage.setMockInitialValues({if (totp != null) 'mfa_totp_uri': totp});
      final mock = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET') {
          return http.Response('<form><input type="password"></form>', 200, request: request);
        }
        final isCode = request.method == 'POST' && request.bodyFields.containsKey(field);
        if (path == '/SRB001/SRB001Page' && !isCode) return http.Response(page, 200, request: request);
        // Codes go to the form's action, or back to the page itself when the
        // form has none (as on SIT's page).
        if (isCode) {
          final code = request.bodyFields[field];
          codesSeen.add(code);
          expect(request.bodyFields['Context'], 'ctx');
          final ok = acceptCode && code == config.codeAt(DateTime.now());
          return http.Response(
              ok ? relayPage : codePage.replaceFirst('<form', '<div id="errorText">Wrong code</div><form'), 200,
              request: request);
        }
        if (path == '/Account/LoginCallbak') {
          return http.Response('', 200, request: request, headers: {'set-cookie': '.AspNet.Cookies=abc; Path=/'});
        }
        return http.Response('not found', 404);
      });
      return AuthService(SessionClient(mock), SecureStorage());
    }

    test('fills in the current code and finishes signing in', () async {
      final auth = await service(totp: config.toUri());
      final challenges = <MfaChallenge>[];
      final ok = await auth.login('2100000', 'pw', onMfaChallenge: challenges.add);
      auth.dispose();

      expect(ok, isTrue);
      expect(codesSeen, hasLength(1));
      expect(challenges.single.automatic, isTrue);
    });

    test('handles the real SIT ADFS verification code page', () async {
      // Structure of SIT's ADFS Azure MFA code page (Context shortened):
      // the code box is in loginForm, which has no action, and a second
      // "options" form switches method.
      const sitPage = '''
        <div id="loginArea">
          <form method="post" id="loginForm" autocomplete="off">
            <input id="authMethod" type="hidden" name="AuthMethod" value="AzureMfaAuthentication">
            <input id="context" type="hidden" name="Context" value="ctx">
            <input type="hidden" name="__EVENTTARGET" id="__EVENTTARGET" value="">
            <div id="instructionsDiv"><p id="instructions">Enter the verification code from your mobile app or hardware token.</p></div>
            <div id="verificationCodeDiv">
              <label id="verificationCode" for="verificationCodeInput">Verification code</label>
              <input id="verificationCodeInput" name="VerificationCode" type="text" value="" placeholder="Enter your verification code">
            </div>
            <div id="errorDiv" style="display: none;"><p id="errorText"></p></div>
            <input id="signInButton" type="submit" name="SignIn" value="Sign in">
            <a id="differentVerificationOption" href="#">Use a different verification option</a>
          </form>
        </div>
        <div id="authOptions">
          <form id="options" method="post" action="https://fs.example.edu/adfs/ls/idpinitiatedsignon.asmx">
            <input id="optionSelection" type="hidden" name="AuthMethod">
            <input id="userNameInputOptionsHolder" name="UserName" value="2100000@sit.singaporetech.edu.sg" type="hidden">
          </form>
        </div>''';
      final auth = await service(totp: config.toUri(), page: sitPage);
      final challenges = <MfaChallenge>[];
      final ok = await auth.login('2100000', 'pw', onMfaChallenge: challenges.add);
      auth.dispose();

      expect(ok, isTrue);
      expect(codesSeen, hasLength(1));
      expect(challenges.single.automatic, isTrue);
    });

    test('finds a generically named code box by its hints', () async {
      // One visible box, named generically, with a numeric keyboard hint.
      final generic = codePage.replaceFirst('<input type="text" name="VerificationCode" autocomplete="off"/>',
          '<input type="text" name="Response" inputmode="numeric" maxlength="6"/>');
      final auth = await service(totp: config.toUri(), page: generic, field: 'Response');
      final ok = await auth.login('2100000', 'pw');
      auth.dispose();
      expect(ok, isTrue);
      expect(codesSeen, hasLength(1));
    });

    test('retries once with a fresh code, then reports the rejection', () async {
      final auth = await service(totp: config.toUri(), acceptCode: false);
      await expectLater(
        auth.login('2100000', 'pw'),
        throwsA(isA<MfaException>().having((e) => e.message, 'message', contains('Wrong code'))),
      );
      auth.dispose();
      expect(codesSeen, hasLength(2));
    });

    test('explains what to do when no code secret is saved', () async {
      final auth = await service();
      await expectLater(
        auth.login('2100000', 'pw'),
        throwsA(isA<MfaException>().having((e) => e.message, 'message', contains('automatic codes'))),
      );
      auth.dispose();
      expect(codesSeen, isEmpty);
    });
  });

  group('Single sign-on to another app that asks for MFA again', () {
    const secret = 'JBSWY3DPEHPK3PXP';
    final config = TotpConfig.parse(secret);
    final target = Uri.parse('https://in4sit.example.edu/psc/schedule');
    final adfs = Uri.parse('https://fs.example.edu/adfs/ls/?wa=wsignin1.0');

    const mfaPage = '''
      <html><body>
        <form method="post" action="/adfs/ls/?wa=wsignin1.0&amp;client-request-id=2">
          <input type="hidden" name="AuthMethod" value="AzureMfaAuthentication"/>
          <input type="hidden" name="Context" value="ctx2"/>
          <input type="text" name="VerificationCode"/>
          <input type="submit" name="SignIn" value="Sign in"/>
        </form>
      </body></html>''';
    const relayPage = '''
      <html><body>
        <form method="POST" action="https://in4sit.example.edu/psp/login">
          <input type="hidden" name="wa" value="wsignin1.0"/>
          <input type="hidden" name="wresult" value="token"/>
        </form>
      </body></html>''';

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('completes the MFA page without a password page and lands on the app', () async {
      FlutterSecureStorage.setMockInitialValues({'mfa_totp_uri': config.toUri()});
      var signedIn = false;
      String? codeSent;
      final mock = MockClient((request) async {
        if (request.url.host == target.host && request.method == 'GET') {
          return signedIn
              ? http.Response('<html>schedule</html>', 200, request: request)
              // Not signed in yet: the app bounces to ADFS, which asks only for MFA.
              : http.Response(mfaPage, 200, request: http.Request('GET', adfs));
        }
        if (request.url.host == adfs.host && request.method == 'POST') {
          codeSent = request.bodyFields['VerificationCode'];
          expect(request.bodyFields['Context'], 'ctx2');
          return http.Response(relayPage, 200, request: request);
        }
        if (request.url.path == '/psp/login') {
          signedIn = true;
          return http.Response('', 200, request: request);
        }
        return http.Response('not found', 404, request: request);
      });
      final auth = AuthService(SessionClient(mock), SecureStorage());

      final response = await auth.getWithSso(target);
      auth.dispose();

      expect(codeSent, config.codeAt(DateTime.now()));
      expect(response.request?.url.host, target.host);
      expect(response.body, contains('schedule'));
    });
  });
}
