import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Console logging that is compiled out of release builds, so URLs and page
/// contents from the sign-in flow never reach the device log in production.
void debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}

class SessionClient extends http.BaseClient {
  /// Logs cookie set/delete events (names only, never values) for debugging.
  static bool debugCookies = false;

  final http.Client _inner;
  final List<_Cookie> _cookies = [];

  SessionClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.BaseRequest currentRequest = request;
    int redirectCount = 0;

    while (true) {
      currentRequest.followRedirects = false;
      _attachCookies(currentRequest);
      currentRequest.headers['user-agent'] =
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36";

      final response = await _inner.send(currentRequest);
      if (debugCookies) {
        final loc = response.headers['location'];
        debugLog('Hop: ${currentRequest.method} ${currentRequest.url.host}${currentRequest.url.path} '
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

        await response.stream.drain();

        String newMethod = currentRequest.method;
        if ((response.statusCode == 301 ||
                response.statusCode == 302 ||
                response.statusCode == 303) &&
            currentRequest.method == 'POST') {
          newMethod = 'GET';
        }

        final next = http.Request(newMethod, newUri);
        // 307/308 must replay the same method *and body*.
        if (newMethod != 'GET' && currentRequest is http.Request) {
          next.bodyBytes = currentRequest.bodyBytes;
          final contentType = currentRequest.headers['content-type'];
          if (contentType != null) next.headers['content-type'] = contentType;
        }
        currentRequest = next;
      } else {
        return response;
      }
    }
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
    final validCookies =
        _cookies.where((cookie) => !cookie.isExpired && cookie.matches(host, path));

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

  void _updateCookies(Map<String, String> headers, Uri requestUrl) {
    final rawCookie = headers['set-cookie'];
    if (rawCookie == null) return;
    final host = requestUrl.host;

    final parts = rawCookie.split(RegExp(r',\s*(?=[^=;\s]+\=)'));
    for (var part in parts) {
      final segments = part.split(';').map((segment) => segment.trim()).toList();
      if (segments.isEmpty) continue;

      final cookieKv = segments.first;
      final eqIdx = cookieKv.indexOf('=');
      if (eqIdx == -1) continue;

      final name = cookieKv.substring(0, eqIdx).trim();
      final value = cookieKv.substring(eqIdx + 1).trim();

      var domain = host;
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
          domain = attrValue;
        } else if (attrName == 'path' && attrValue.isNotEmpty) {
          path = attrValue;
        } else if (attrName == 'expires' && attrValue.isNotEmpty) {
          expires = _parseCookieDate(attrValue);
        } else if (attrName == 'max-age') {
          final seconds = int.tryParse(attrValue);
          if (seconds != null) {
            maxAgeExpiry = DateTime.now().toUtc().add(Duration(seconds: seconds));
          }
        }
      }

      // Max-Age wins over Expires.
      final effectiveExpiry = maxAgeExpiry ?? expires;

      // A cookie is identified by name + domain + path. Whatever the server
      // sends replaces the one with that identity, and a deletion (empty
      // value or already expired) must not touch cookies on other paths, e.g.
      // ADFS sends new MSISAuth cookies and clears old ones in one response.
      _cookies.removeWhere((cookie) =>
          cookie.name == name && cookie.domain == domain && cookie.path == path);
      final cookie = _Cookie(name, value, domain, path, effectiveExpiry);
      final isDelete = value.isEmpty || value.toLowerCase() == 'deleted' || cookie.isExpired;
      if (debugCookies) {
        debugLog('Cookie $host: ${isDelete ? "DELETE" : "SET"} $name '
            'domain=$domain path=$path expires=$effectiveExpiry');
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
    return _cookies
        .where((c) => !c.isExpired && c.matches(url.host, path))
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

  _Cookie(this.name, this.value, this.domain, this.path, [this.expires]);

  bool get isExpired => expires != null && expires!.isBefore(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expires': expires?.millisecondsSinceEpoch,
      };

  factory _Cookie.fromJson(Map<String, dynamic> json) {
    final exp = json['expires'] as int?;
    return _Cookie(
      json['name'] as String,
      json['value'] as String,
      json['domain'] as String,
      json['path'] as String,
      exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
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

    final normalizedRequestPath = requestPath.isEmpty ? '/' : requestPath;
    return normalizedRequestPath.startsWith(path);
  }
}
