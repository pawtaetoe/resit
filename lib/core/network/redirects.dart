import 'package:http/http.dart' as http;

/// A redirect [SessionClient] refused to follow: to a non-https address, or
/// a 307/308 that would resend the request body to another origin.
class UnsafeRedirectException implements Exception {
  final String message;
  UnsafeRedirectException(this.message);

  @override
  String toString() => message;
}

/// Whether [statusCode] is a redirect that [SessionClient] follows itself.
bool isRedirectStatus(int statusCode) =>
    statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308;

/// The request to send after [request] was answered with a [statusCode]
/// redirect to [location]. Throws [UnsafeRedirectException] when following
/// it would leave https, or resend a body to another origin.
http.Request redirectRequest(http.BaseRequest request, int statusCode, String location) {
  final host = request.url.host;
  final newUri = request.url.resolve(location);

  String newMethod = request.method;
  if ((statusCode == 301 || statusCode == 302 || statusCode == 303) && request.method == 'POST') {
    newMethod = 'GET';
  }
  final replaysBody = newMethod != 'GET' && newMethod != 'HEAD';

  // Never leave TLS: cookies (and any resent body) would go out in the
  // clear.
  if (newUri.scheme != 'https') {
    throw UnsafeRedirectException('Refused a redirect from $host to an insecure ${newUri.scheme}: address.');
  }
  // 307/308 resend the method *and body*: only ever to the same origin,
  // so a form (e.g. credentials) can't be bounced to another site.
  if (replaysBody && _origin(newUri) != _origin(request.url)) {
    throw UnsafeRedirectException('Refused to resend a ${request.method} from $host to '
        '${newUri.host} ($statusCode redirect).');
  }

  final next = http.Request(newMethod, newUri);
  if (replaysBody && request is http.Request) {
    next.bodyBytes = request.bodyBytes;
    final contentType = request.headers['content-type'];
    if (contentType != null) next.headers['content-type'] = contentType;
  }
  return next;
}

String _origin(Uri uri) => '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
