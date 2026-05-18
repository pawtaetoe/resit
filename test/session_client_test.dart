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
}
