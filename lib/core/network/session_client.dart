import 'package:http/http.dart' as http;

class SessionClient extends http.BaseClient {
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
      _updateCookies(response.headers, currentRequest.url.host);

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

        currentRequest = http.Request(newMethod, newUri);
      } else {
        return response;
      }
    }
  }

  void _attachCookies(http.BaseRequest request) {
    final host = request.url.host;
    final path = request.url.path.isEmpty ? '/' : request.url.path;
    final validCookies = _cookies.where((cookie) => cookie.matches(host, path));

    if (validCookies.isNotEmpty) {
      request.headers['cookie'] = validCookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    }
  }

  void _updateCookies(Map<String, String> headers, String host) {
    final rawCookie = headers['set-cookie'];
    if (rawCookie == null) return;

    final parts = rawCookie.split(RegExp(r',\s*(?=[^=;\s]+\=)'));
    for (var part in parts) {
      final segments = part.split(';').map((segment) => segment.trim()).toList();
      if (segments.isEmpty) continue;

      final cookieKv = segments.first;
      final eqIdx = cookieKv.indexOf('=');
      if (eqIdx == -1) continue;

      final name = cookieKv.substring(0, eqIdx).trim();
      final value = cookieKv.substring(eqIdx + 1).trim();
      if (value.isEmpty || value.toLowerCase() == 'deleted') {
        _cookies.removeWhere((cookie) => cookie.name == name && cookie.domain == host);
        continue;
      }

      var domain = host;
      var path = '/';
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
        }
      }

      _cookies.removeWhere((cookie) =>
          cookie.name == name && cookie.domain == domain && cookie.path == path);
      _cookies.add(_Cookie(name, value, domain, path));
    }
  }

  void clearCookies() {
    _cookies.clear();
  }

  bool hasAuthCookie() {
    return _cookies.any((cookie) =>
        cookie.name == '.AspNet.Cookies' || cookie.name == 'AspNet.Cookies');
  }
}

class _Cookie {
  final String name;
  final String value;
  final String domain;
  final String path;

  _Cookie(this.name, this.value, this.domain, this.path);

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
