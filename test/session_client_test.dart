import 'dart:async';

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

  group('cookie attributes', () {
    test('a Secure cookie is only sent over https', () async {
      final sent = <String, String?>{};
      final session = SessionClient(MockClient((request) async {
        if (request.url.path == '/set') {
          return http.Response('', 200, headers: {'set-cookie': 'S=1; Path=/; Secure, P=2; Path=/'});
        }
        sent[request.url.scheme] = request.headers['cookie'];
        return http.Response('ok', 200);
      }));

      await session.get(Uri.parse('https://example.com/set'));
      await session.get(Uri.parse('https://example.com/page'));
      await session.get(Uri.parse('http://example.com/page'));

      expect(sent['https'], 'S=1; P=2');
      expect(sent['http'], 'P=2');
      expect(session.cookieNamesFor(Uri.parse('http://example.com/')), ['P']);
    });

    test('an http response cannot set a Secure cookie', () async {
      final session = SessionClient(MockClient((request) async {
        return http.Response('', 200, headers: {'set-cookie': 'S=1; Path=/; Secure'});
      }));
      await session.get(Uri.parse('http://example.com/'));
      expect(session.hasCookies, isFalse);
    });

    test('a Domain the request host does not belong to is rejected', () async {
      final session = SessionClient(MockClient((request) async {
        return http.Response('', 200, headers: {
          'set-cookie': 'Evil=1; Domain=attacker.example; Path=/, '
              'Tld=1; Domain=com; Path=/, '
              'Sibling=1; Domain=other.example.com; Path=/, '
              'Parent=1; Domain=example.com; Path=/',
        });
      }));
      await session.get(Uri.parse('https://sso.example.com/'));

      expect(session.cookieNamesFor(Uri.parse('https://attacker.example/')), isEmpty);
      expect(session.cookieNamesFor(Uri.parse('https://other.example.com/')), ['Parent']);
      // Domain=example.com (no leading dot) is a domain cookie too.
      expect(session.cookieNamesFor(Uri.parse('https://app.example.com/')), ['Parent']);
      expect(session.cookieNamesFor(Uri.parse('https://sso.example.com/')), ['Parent']);
    });

    test('a jar saved before the Secure flag existed still loads', () async {
      const old = '[{"name":".AspNet.Cookies","value":"abc","domain":"rbs.example.com","path":"/","expires":null},'
          '{"name":"MSISAuth","value":"x","domain":".example.com","path":"/adfs","expires":4102444800000}]';
      final session = SessionClient(MockClient((request) async {
        return http.Response(request.headers['cookie'] ?? '', 200);
      }));
      session.importCookies(old);

      expect(session.hasAuthCookie(), isTrue);
      expect((await session.get(Uri.parse('https://rbs.example.com/'))).body, '.AspNet.Cookies=abc');
      expect((await session.get(Uri.parse('https://fs.example.com/adfs/ls'))).body, 'MSISAuth=x');

      // And the flag survives a save and restore.
      final secure = SessionClient(MockClient((request) async {
        return http.Response('', 200, headers: {'set-cookie': 'S=1; Path=/; Secure'});
      }));
      await secure.get(Uri.parse('https://example.com/'));
      final restored = SessionClient(MockClient((request) async => http.Response(request.headers['cookie'] ?? '', 200)))
        ..importCookies(secure.exportCookies());
      expect((await restored.get(Uri.parse('http://example.com/'))).body, isEmpty);
      expect((await restored.get(Uri.parse('https://example.com/'))).body, 'S=1');
    });
  });

  group('redirects', () {
    test('a redirect to plain http is refused', () async {
      final requested = <Uri>[];
      final session = SessionClient(MockClient((request) async {
        requested.add(request.url);
        return http.Response('', 302, headers: {'location': 'http://example.com/insecure'});
      }));
      await expectLater(session.get(Uri.parse('https://example.com/')), throwsA(isA<UnsafeRedirectException>()));
      expect(requested, hasLength(1));
    });

    test('a 307 to another origin does not resend the body', () async {
      final requested = <Uri>[];
      final session = SessionClient(MockClient((request) async {
        requested.add(request.url);
        return http.Response('', 307, headers: {'location': 'https://attacker.example/collect'});
      }));
      await expectLater(
        session.post(Uri.parse('https://fs.example.com/adfs/ls/'), body: {'Password': 'secret'}),
        throwsA(isA<UnsafeRedirectException>()),
      );
      expect(requested.map((u) => u.host), ['fs.example.com']);
    });

    test('a 308 on the same origin resends the body', () async {
      final session = SessionClient(MockClient((request) async {
        if (request.url.path == '/old') {
          return http.Response('', 308, headers: {'location': '/new'});
        }
        return http.Response('${request.method} ${request.bodyFields['a']}', 200);
      }));
      final response = await session.post(Uri.parse('https://example.com/old'), body: {'a': '1'});
      expect(response.body, 'POST 1');
    });

    test('a 302 after a POST becomes a GET, even to another origin', () async {
      final session = SessionClient(MockClient((request) async {
        if (request.url.host == 'a.example.com') {
          return http.Response('', 302, headers: {'location': 'https://b.example.com/landed'});
        }
        return http.Response('${request.method} ${request.body}', 200, request: request);
      }));
      final response = await session.post(Uri.parse('https://a.example.com/form'), body: {'a': '1'});
      expect(response.body, 'GET ');
      expect(response.request?.url.host, 'b.example.com');
    });
  });

  group('timeouts', () {
    testWidgets('a request that never answers fails after the default timeout', (tester) async {
      final session = SessionClient(MockClient((_) => Completer<http.Response>().future));
      Object? error;
      unawaited(session.get(Uri.parse('https://example.com/')).then<void>((_) {}, onError: (Object e) => error = e));

      await tester.pump(SessionClient.defaultTimeout - const Duration(seconds: 1));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(error, isA<TimeoutException>());
    });

    test('withTimeout gives a call its own limit', () async {
      final session = SessionClient(MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('late', 200);
      }));

      await expectLater(
        session.withTimeout(const Duration(milliseconds: 20), () => session.get(Uri.parse('https://example.com/'))),
        throwsA(isA<TimeoutException>()),
      );
      // A longer limit (or none) lets a slow answer through.
      final slow = await session.withTimeout(
          const Duration(seconds: 5), () => session.get(Uri.parse('https://example.com/')));
      expect(slow.body, 'late');
      final unlimited = await session.withTimeout(null, () => session.get(Uri.parse('https://example.com/')));
      expect(unlimited.body, 'late');
    });

    test('a body that stalls part-way fails too', () async {
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final session = SessionClient(MockClient.streaming((request, _) async {
        body.add([104, 105]); // "hi", then nothing more
        return http.StreamedResponse(body.stream, 200);
      }));
      await expectLater(
        session.withTimeout(const Duration(milliseconds: 50), () => session.get(Uri.parse('https://example.com/'))),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
