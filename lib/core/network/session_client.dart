import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Console logging that is compiled out of release builds, so URLs and page
/// contents from the sign-in flow never reach the device log in production.
void debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}

/// A redirect [SessionClient] refused to follow: to a non-https address, or
/// a 307/308 that would resend the request body to another origin.
class UnsafeRedirectException implements Exception {
  final String message;
  UnsafeRedirectException(this.message);

  @override
  String toString() => message;
}

/// Holds a per-zone request timeout set by [SessionClient.withTimeout]
/// (wrapped so that "no timeout" can be told apart from "not set").
class _TimeoutSetting {
  final Duration? timeout;
  const _TimeoutSetting(this.timeout);
}

/// Suffixes under which anyone can register a site: a cookie may not be
/// scoped to one of these.
const _publicSuffixes = {'sg', 'edu.sg', 'com.sg', 'gov.sg', 'org.sg', 'net.sg', 'per.sg'};

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
  final List<_Cookie> _cookies = [];

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
      _attachCookies(currentRequest);
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
      _updateCookies(response.headers, currentRequest.url);

      final isRedirect = response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308;

      if (isRedirect && response.headers.containsKey('location')) {
        redirectCount++;
        if (redirectCount > 10) throw Exception("Too many redirects");

        final location = response.headers['location']!;
        final newUri = currentRequest.url.resolve(location);

        String newMethod = currentRequest.method;
        if ((response.statusCode == 301 ||
                response.statusCode == 302 ||
                response.statusCode == 303) &&
            currentRequest.method == 'POST') {
          newMethod = 'GET';
        }
        final replaysBody = newMethod != 'GET' && newMethod != 'HEAD';

        // Never leave TLS: cookies (and any resent body) would go out in the
        // clear.
        if (newUri.scheme != 'https') {
          _discard(response);
          throw UnsafeRedirectException(
              'Refused a redirect from $host to an insecure ${newUri.scheme}: address.');
        }
        // 307/308 resend the method *and body*: only ever to the same origin,
        // so a form (e.g. credentials) can't be bounced to another site.
        if (replaysBody && _origin(newUri) != _origin(currentRequest.url)) {
          _discard(response);
          throw UnsafeRedirectException('Refused to resend a ${currentRequest.method} from $host to '
              '${newUri.host} (${response.statusCode} redirect).');
        }

        await response.stream.drain<void>();

        final next = http.Request(newMethod, newUri);
        if (replaysBody && currentRequest is http.Request) {
          next.bodyBytes = currentRequest.bodyBytes;
          final contentType = currentRequest.headers['content-type'];
          if (contentType != null) next.headers['content-type'] = contentType;
        }
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

  static String _origin(Uri uri) => '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';

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

  void _attachCookies(http.BaseRequest request) {
    final host = request.url.host;
    final path = request.url.path.isEmpty ? '/' : request.url.path;
    final secure = request.url.scheme == 'https';
    final validCookies = _cookies.where(
        (cookie) => !cookie.isExpired && cookie.matches(host, path) && (secure || !cookie.secure));

    if (validCookies.isNotEmpty) {
      request.headers['cookie'] = validCookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    }
  }

  /// RFC 6265 default-path: the directory of the request path.
  String _defaultPath(String requestPath) {
    if (!requestPath.startsWith('/')) return '/';
    final lastSlash = requestPath.lastIndexOf('/');
    return lastSlash == 0 ? '/' : requestPath.substring(0, lastSlash);
  }

  /// RFC 6265 5.1.3 domain-match: [host] is [domain] or a subdomain of it,
  /// and not an IP address.
  static bool _domainMatches(String host, String domain) {
    if (host == domain) return true;
    final isIp = RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':');
    return !isIp && host.endsWith('.$domain');
  }

  void _updateCookies(Map<String, String> headers, Uri requestUrl) {
    final rawCookie = headers['set-cookie'];
    if (rawCookie == null) return;
    final host = requestUrl.host.toLowerCase();
    final fromSecure = requestUrl.scheme == 'https';

    final parts = rawCookie.split(RegExp(r',\s*(?=[^=;\s]+\=)'));
    for (var part in parts) {
      final segments = part.split(';').map((segment) => segment.trim()).toList();
      if (segments.isEmpty) continue;

      final cookieKv = segments.first;
      final eqIdx = cookieKv.indexOf('=');
      if (eqIdx == -1) continue;

      final name = cookieKv.substring(0, eqIdx).trim();
      final value = cookieKv.substring(eqIdx + 1).trim();

      // Host-only cookies are stored under the bare host; Domain cookies
      // under ".domain" (see [_Cookie.matches]).
      var domain = host;
      var rejected = false;
      var secure = false;
      var path = _defaultPath(requestUrl.path);
      DateTime? expires;
      DateTime? maxAgeExpiry;
      for (var i = 1; i < segments.length; i++) {
        final attr = segments[i];
        final attrEq = attr.indexOf('=');
        final attrName = attrEq == -1
            ? attr.toLowerCase()
            : attr.substring(0, attrEq).trim().toLowerCase();
        final attrValue = attrEq == -1 ? '' : attr.substring(attrEq + 1).trim();

        if (attrName == 'domain' && attrValue.isNotEmpty) {
          // RFC 6265 5.2.3 and 5.3 step 6: a leading dot is ignored, and a
          // Domain the request host doesn't domain-match (another site, or a
          // bare TLD) means the whole cookie is ignored.
          var d = attrValue.toLowerCase();
          if (d.startsWith('.')) d = d.substring(1);
          // A public suffix (edu.sg, com.sg, ...) is refused too, so one SIT
          // site can't set a cookie for every *.edu.sg site.
          if (d.isEmpty || !d.contains('.') || _publicSuffixes.contains(d) || !_domainMatches(host, d)) {
            rejected = true;
          } else {
            domain = '.$d';
          }
        } else if (attrName == 'path' && attrValue.startsWith('/')) {
          path = attrValue;
        } else if (attrName == 'secure') {
          secure = true;
        } else if (attrName == 'expires' && attrValue.isNotEmpty) {
          expires = _parseCookieDate(attrValue);
        } else if (attrName == 'max-age') {
          final seconds = int.tryParse(attrValue);
          if (seconds != null) {
            maxAgeExpiry = DateTime.now().toUtc().add(Duration(seconds: seconds));
          }
        }
      }

      // Only a secure origin may set (or replace) a Secure cookie.
      if (secure && !fromSecure) rejected = true;
      if (rejected) {
        if (debugCookies) debugLog('Cookie $host: IGNORED $name (domain/secure attributes not allowed)');
        continue;
      }

      // Max-Age wins over Expires.
      final effectiveExpiry = maxAgeExpiry ?? expires;

      // A cookie is identified by name + domain + path. Whatever the server
      // sends replaces the one with that identity, and a deletion (empty
      // value or already expired) must not touch cookies on other paths, e.g.
      // ADFS sends new MSISAuth cookies and clears old ones in one response.
      _cookies.removeWhere((cookie) =>
          cookie.name == name && cookie.domain == domain && cookie.path == path);
      final cookie = _Cookie(name, value, domain, path, effectiveExpiry, secure);
      final isDelete = value.isEmpty || value.toLowerCase() == 'deleted' || cookie.isExpired;
      if (debugCookies) {
        debugLog('Cookie $host: ${isDelete ? "DELETE" : "SET"} $name '
            'domain=$domain path=$path secure=$secure expires=$effectiveExpiry');
      }
      if (!isDelete) _cookies.add(cookie);
    }
  }

  void clearCookies() {
    _cookies.clear();
  }

  bool hasAuthCookie() {
    return _cookies.any((cookie) =>
        !cookie.isExpired &&
        (cookie.name == '.AspNet.Cookies' || cookie.name == 'AspNet.Cookies'));
  }

  /// Names (never values) of the live cookies that would be sent to [url].
  List<String> cookieNamesFor(Uri url) {
    final path = url.path.isEmpty ? '/' : url.path;
    final secure = url.scheme == 'https';
    return _cookies
        .where((c) => !c.isExpired && c.matches(url.host, path) && (secure || !c.secure))
        .map((c) => c.name)
        .toList();
  }

  bool get hasCookies => _cookies.any((cookie) => !cookie.isExpired);

  /// Serialises the live cookies (including session-only ones) so the
  /// session can survive an app restart.
  String exportCookies() {
    return jsonEncode(
        _cookies.where((c) => !c.isExpired).map((c) => c.toJson()).toList());
  }

  void importCookies(String json) {
    _cookies.clear();
    final list = jsonDecode(json) as List<dynamic>;
    for (final item in list) {
      final cookie = _Cookie.fromJson(Map<String, dynamic>.from(item as Map));
      if (!cookie.isExpired) _cookies.add(cookie);
    }
  }
}

DateTime? _parseCookieDate(String raw) {
  final cleaned = raw.trim().replaceAll('-', ' ');
  for (final pattern in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEE, d MMM yyyy HH:mm:ss 'GMT'"]) {
    try {
      return DateFormat(pattern, 'en_US').parseUtc(cleaned);
    } catch (_) {}
  }
  return null;
}

class _Cookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;

  /// Only sent over https.
  final bool secure;

  _Cookie(this.name, this.value, this.domain, this.path, [this.expires, this.secure = false]);

  bool get isExpired => expires != null && expires!.isBefore(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expires': expires?.millisecondsSinceEpoch,
        if (secure) 'secure': true,
      };

  /// Also reads jars saved before `secure` existed (it defaults to false).
  factory _Cookie.fromJson(Map<String, dynamic> json) {
    final exp = json['expires'] as int?;
    return _Cookie(
      json['name'] as String,
      json['value'] as String,
      json['domain'] as String,
      json['path'] as String,
      exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      json['secure'] == true,
    );
  }

  bool matches(String host, String requestPath) {
    final normalizedHost = host.toLowerCase();
    final normalizedDomain = domain.toLowerCase();

    final hostMatches = normalizedDomain.startsWith('.')
        ? normalizedHost == normalizedDomain.substring(1) ||
            normalizedHost.endsWith(normalizedDomain)
        : normalizedHost == normalizedDomain;

    if (!hostMatches) return false;

    // RFC 6265 5.1.4: "/psc" matches "/psc" and "/psc/x", not "/pscx".
    final normalizedRequestPath = requestPath.isEmpty ? '/' : requestPath;
    if (normalizedRequestPath == path) return true;
    if (!normalizedRequestPath.startsWith(path)) return false;
    return path.endsWith('/') || normalizedRequestPath[path.length] == '/';
  }
}
