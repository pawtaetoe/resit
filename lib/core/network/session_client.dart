import 'package:http/http.dart' as http;

class SessionClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  // Outer map key is the domain (host), inner map is cookie key-value pairs.
  final Map<String, Map<String, String>> _cookies = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.BaseRequest currentRequest = request;
    int redirectCount = 0;

    while (true) {
      currentRequest.followRedirects = false;
      
      final host = currentRequest.url.host;
      if (_cookies.containsKey(host) && _cookies[host]!.isNotEmpty) {
        final cookieString = _cookies[host]!.entries.map((e) => '${e.key}=${e.value}').join('; ');
        currentRequest.headers['cookie'] = cookieString;
      }
      currentRequest.headers['user-agent'] =
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36";

      final response = await _inner.send(currentRequest);
      _updateCookies(response.headers, host);

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

        await response.stream.drain(); // Drain body of redirect response

        // For 301, 302, 303, change POST to GET to mimic Python 'requests' behavior
        String newMethod = currentRequest.method;
        if (response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303) {
          if (currentRequest.method == 'POST') {
            newMethod = 'GET';
          }
        }

        currentRequest = http.Request(newMethod, newUri);
      } else {
        return response;
      }
    }
  }

  void _updateCookies(Map<String, String> headers, String host) {
    final rawCookie = headers['set-cookie'];
    if (rawCookie != null) {
      _cookies.putIfAbsent(host, () => {});
      final parts = rawCookie.split(RegExp(r',\s*(?=[a-zA-Z0-9_.-]+=)'));
      for (var part in parts) {
        final cookieKV = part.split(';').first;
        final eqIdx = cookieKV.indexOf('=');
        if (eqIdx != -1) {
          final key = cookieKV.substring(0, eqIdx).trim();
          final val = cookieKV.substring(eqIdx + 1).trim();
          if (val.isEmpty || val.toLowerCase() == 'deleted') {
            _cookies[host]!.remove(key);
          } else {
            _cookies[host]![key] = val;
          }
        }
      }
    }
  }

  void clearCookies() {
    _cookies.clear();
  }

  bool hasAuthCookie() {
    for (var domainCookies in _cookies.values) {
      if (domainCookies.containsKey('.AspNet.Cookies')) return true;
    }
    return false;
  }
}
