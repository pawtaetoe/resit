import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:resit/core/network/cookie_jar.dart';
import 'package:resit/core/network/debug_log.dart';
import 'package:resit/core/network/redirects.dart';

// The cookie rules and redirect rules live next to this file; importing this
// one brings in what callers need.
export 'package:resit/core/network/debug_log.dart' show debugLog;
export 'package:resit/core/network/redirects.dart' show UnsafeRedirectException;

/// Holds a per-zone request timeout set by [SessionClient.withTimeout]
/// (wrapped so that "no timeout" can be told apart from "not set").
class _TimeoutSetting {
  final Duration? timeout;
  const _TimeoutSetting(this.timeout);
}

class SessionClient extends http.BaseClient {
  /// A browser's user agent, because SIT's sign-in only offers its web
  /// sign-in pages to browsers, followed by an honest "reSIT" token so SIT's
  /// IT can tell the app's requests apart in their logs.
  static const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/148.0.0.0 Safari/537.36 reSIT/1.0 (unofficial SIT student app)';

  /// Logs cookie set/delete events (names only, never values) for debugging.
  static bool debugCookies = false;

  /// How long a request may take (waiting for the response headers, and
  /// then between chunks of the body) unless [withTimeout] says otherwise.
  /// Without it a stalled connection would hold up everything queued behind
  /// it forever.
  static const Duration defaultTimeout = Duration(seconds: 30);

  static final Object _timeoutKey = Object();

  final http.Client _inner;
  final CookieJar _cookies = CookieJar();

  SessionClient([http.Client? inner]) : _inner = inner ?? http.Client();

  /// Runs [body] with every request it makes through this client allowed
  /// [timeout] instead of [defaultTimeout]; null means no limit at all (the
  /// caller enforces its own). For calls that legitimately wait long, such
  /// as ADFS holding an MFA poll open until the phone approves.
  Future<T> withTimeout<T>(Duration? timeout, Future<T> Function() body) {
    return runZoned(body, zoneValues: {_timeoutKey: _TimeoutSetting(timeout)});
  }

  Duration? get _currentTimeout {
    final setting = Zone.current[_timeoutKey];
    return setting is _TimeoutSetting ? setting.timeout : defaultTimeout;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final timeout = _currentTimeout;
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    http.BaseRequest currentRequest = request;
    int redirectCount = 0;

    while (true) {
      currentRequest.followRedirects = false;
      final cookie = _cookies.headerFor(currentRequest.url);
      if (cookie != null) currentRequest.headers['cookie'] = cookie;
      currentRequest.headers['user-agent'] = userAgent;

      final host = currentRequest.url.host;
      final pending = _inner.send(currentRequest);
      final response = deadline == null
          ? await pending
          : await pending.timeout(
              _remaining(deadline),
              onTimeout: () => throw TimeoutException('No response from $host in time.', timeout),
            );
      if (debugCookies) {
        final loc = response.headers['location'];
        debugLog('Hop: ${currentRequest.method} $host${currentRequest.url.path} '
            '-> ${response.statusCode}'
            '${loc != null ? " Location: ${_describeLocation(currentRequest.url, loc)}" : ""}');
      }
      _cookies.updateFrom(response.headers, currentRequest.url, log: debugCookies);

      if (isRedirectStatus(response.statusCode) && response.headers.containsKey('location')) {
        redirectCount++;
        if (redirectCount > 10) throw Exception("Too many redirects");

        final http.Request next;
        try {
          next = redirectRequest(currentRequest, response.statusCode, response.headers['location']!);
        } on UnsafeRedirectException {
          _discard(response);
          rethrow;
        }

        await response.stream.drain<void>();
        currentRequest = next;
      } else {
        return timeout == null ? response : _withBodyTimeout(response, timeout);
      }
    }
  }

  static void _discard(http.StreamedResponse response) {
    unawaited(response.stream.drain<void>().catchError((_) {}));
  }

  static Duration _remaining(DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// [response] with its body failing with a [TimeoutException] if it
  /// stalls for longer than [timeout] between chunks.
  static http.StreamedResponse _withBodyTimeout(http.StreamedResponse response, Duration timeout) {
    final stream = response.stream.timeout(timeout, onTimeout: (sink) {
      sink.addError(TimeoutException('The response from ${response.request?.url.host} stalled.', timeout));
      sink.close();
    });
    return http.StreamedResponse(
      stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Path plus query parameter *names* of a redirect target, for logging.
  String _describeLocation(Uri from, String location) {
    final uri = from.resolve(location);
    final query = uri.queryParameters.keys.join(',');
    return '${uri.host}${uri.path}${query.isEmpty ? "" : "?$query"}';
  }

  void clearCookies() {
    _cookies.clear();
  }

  bool hasAuthCookie() => _cookies.hasAuthCookie();

  /// Names (never values) of the live cookies that would be sent to [url].
  List<String> cookieNamesFor(Uri url) => _cookies.namesFor(url);

  bool get hasCookies => _cookies.hasLiveCookies;

  /// Serialises the live cookies (including session-only ones) so the
  /// session can survive an app restart.
  String exportCookies() => _cookies.exportJson();

  void importCookies(String json) => _cookies.importJson(json);
}
