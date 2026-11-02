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

    Future<AuthService> service({String? totp, bool acceptCode = true}) async {
      FlutterSecureStorage.setMockInitialValues({if (totp != null) 'mfa_totp_uri': totp});
      final mock = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET') {
          return http.Response('<form><input type="password"></form>', 200, request: request);
        }
        if (path == '/SRB001/SRB001Page') return http.Response(codePage, 200, request: request);
        if (path == '/adfs/ls/') {
          final code = request.bodyFields['VerificationCode'];
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
}
