import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';

void main() {
  test('preserves cookies across matching domain and subdomain', () async {
    final mock = MockClient((request) async {
      if (request.url.path == '/set-cookie') {
        return http.Response('', 200, headers: {
          'set-cookie': 'A=1; Domain=.example.com; Path=/; HttpOnly',
        });
      }

      if (request.url.path == '/check-cookie') {
        expect(request.headers['cookie'], 'A=1');
        return http.Response('ok', 200);
      }

      return http.Response('not found', 404);
    });

    final session = SessionClient(mock);
    await session.get(Uri.parse('https://example.com/set-cookie'));
    await session.get(Uri.parse('https://sub.example.com/check-cookie'));
  });

  test('detects auth cookie from set-cookie header', () async {
    final mock = MockClient((request) async {
      return http.Response('', 200, headers: {
        'set-cookie': '.AspNet.Cookies=abc123; Domain=.example.com; Path=/; HttpOnly',
      });
    });

    final session = SessionClient(mock);
    await session.get(Uri.parse('https://example.com/login'));
    expect(session.hasAuthCookie(), isTrue);
  });

  test('exported cookies restore a session in a new client', () async {
    final first = SessionClient(MockClient((request) async {
      return http.Response('', 200, headers: {
        'set-cookie': '.AspNet.Cookies=abc123; Path=/; HttpOnly',
      });
    }));
    await first.get(Uri.parse('https://example.com/login'));

    final restored = SessionClient(MockClient((request) async {
      expect(request.headers['cookie'], '.AspNet.Cookies=abc123');
      return http.Response('ok', 200);
    }));
    restored.importCookies(first.exportCookies());

    expect(restored.hasAuthCookie(), isTrue);
    await restored.get(Uri.parse('https://example.com/page'));
  });

  test('expired cookies are dropped and Max-Age cookies are kept', () async {
    final mock = MockClient((request) async {
      return http.Response('', 200, headers: {
        'set-cookie': 'Old=1; Path=/; Expires=Wed, 01 Jan 2020 00:00:00 GMT, '
            'New=2; Path=/; Max-Age=3600',
      });
    });

    final session = SessionClient(mock);
    await session.get(Uri.parse('https://example.com/'));
    final exported = session.exportCookies();
    expect(exported.contains('"Old"'), isFalse);
    expect(exported.contains('"New"'), isTrue);
  });

  test('a deletion only removes the cookie with the same name, domain and path', () async {
    // ADFS sets new MSISAuth cookies and clears old ones in one response.
    final session = SessionClient(MockClient((request) async {
      if (request.url.path == '/adfs/ls/login') {
        return http.Response('', 200, headers: {
          'set-cookie': 'MSISAuth=new; path=/adfs; HttpOnly; Secure, '
              'MSISAuth=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/adfs/ls',
        });
      }
      expect(request.headers['cookie'], 'MSISAuth=new');
      return http.Response('ok', 200);
    }));

    await session.get(Uri.parse('https://fs.example.com/adfs/ls/login'));
    await session.get(Uri.parse('https://fs.example.com/adfs/ls/next'));
  });

  test('a cookie without a path defaults to the request directory', () async {
    final session = SessionClient(MockClient((request) async {
      if (request.url.path == '/adfs/ls/login') {
        return http.Response('', 200, headers: {'set-cookie': 'X=1'});
      }
      expect(request.headers['cookie'], request.url.path.startsWith('/adfs/ls') ? 'X=1' : isNull);
      return http.Response('ok', 200);
    }));

    await session.get(Uri.parse('https://fs.example.com/adfs/ls/login'));
    await session.get(Uri.parse('https://fs.example.com/adfs/ls/other'));
    await session.get(Uri.parse('https://fs.example.com/elsewhere'));
  });
}
