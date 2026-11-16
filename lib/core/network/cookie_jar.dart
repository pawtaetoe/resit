import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:resit/core/network/debug_log.dart';

/// Suffixes under which anyone can register a site: a cookie may not be
/// scoped to one of these.
const _publicSuffixes = {'sg', 'edu.sg', 'com.sg', 'gov.sg', 'org.sg', 'net.sg', 'per.sg'};

/// The cookies of one session, kept by the RFC 6265 rules: Domain and
/// public-suffix checks, Secure cookies only to and from https, path
/// matching, and expiry by Max-Age or Expires.
class CookieJar {
  final List<_Cookie> _cookies = [];

  /// The live cookies that would be sent to [url].
  Iterable<_Cookie> _sentTo(Uri url) {
    final path = url.path.isEmpty ? '/' : url.path;
    final secure = url.scheme == 'https';
    return _cookies.where((c) => !c.isExpired && c.matches(url.host, path) && (secure || !c.secure));
  }

  /// The `cookie` header for a request to [url], or null when no cookie is
  /// sent there.
  String? headerFor(Uri url) {
    final validCookies = _sentTo(url);
    if (validCookies.isEmpty) return null;
    return validCookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  /// RFC 6265 default-path: the directory of the request path.
  static String _defaultPath(String requestPath) {
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

  /// Stores (or deletes) the cookies in a response's `set-cookie` [headers]
  /// to a request for [requestUrl]. [log] logs each one (names only, never
  /// values).
  void updateFrom(Map<String, String> headers, Uri requestUrl, {bool log = false}) {
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
        if (log) debugLog('Cookie $host: IGNORED $name (domain/secure attributes not allowed)');
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
      if (log) {
        debugLog('Cookie $host: ${isDelete ? "DELETE" : "SET"} $name '
            'domain=$domain path=$path secure=$secure expires=$effectiveExpiry');
      }
      if (!isDelete) _cookies.add(cookie);
    }
  }

  void clear() {
    _cookies.clear();
  }

  bool hasAuthCookie() {
    return _cookies.any((cookie) =>
        !cookie.isExpired &&
        (cookie.name == '.AspNet.Cookies' || cookie.name == 'AspNet.Cookies'));
  }

  /// Names (never values) of the live cookies that would be sent to [url].
  List<String> namesFor(Uri url) => _sentTo(url).map((c) => c.name).toList();

  bool get hasLiveCookies => _cookies.any((cookie) => !cookie.isExpired);

  /// Serialises the live cookies (including session-only ones) so the
  /// session can survive an app restart.
  String exportJson() {
    return jsonEncode(
        _cookies.where((c) => !c.isExpired).map((c) => c.toJson()).toList());
  }

  /// Replaces the jar with cookies saved by [exportJson], dropping any that
  /// have expired since.
  void importJson(String json) {
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
