import 'package:http/http.dart' as http;
import 'package:resit/core/network/session_client.dart';
import 'package:resit/sites/adfs/auth_service.dart';

/// What every request to RBS shares: its address, the form token, and the
/// headers RBS's own pages send with their background (XHR) posts.
class RbsRequests {
  final SessionClient client;
  final AuthService auth;

  static const String base = "https://rbs.singaporetech.edu.sg";

  /// The RBS pages requests are sent from (their referer): room search and
  /// the bookings dashboard.
  static const String searchPage = "$base/SRB001/SRB001Page";
  static const String dashboardPage = "$base/DHB001/DHB001Page";

  /// The accept header of a request that expects JSON back.
  static const String acceptJson = "application/json, text/javascript, */*; q=0.01";

  Future<String?>? _csrfInFlight;

  RbsRequests(this.client, this.auth);

  /// The RBS form token. Requests that start together share one look-up
  /// (the auth service keeps the token itself between look-ups).
  Future<String?> csrfToken() {
    return _csrfInFlight ??= auth.getCsrfToken().whenComplete(() => _csrfInFlight = null);
  }

  /// [csrfToken], failing when there isn't one.
  Future<String> requireCsrfToken() async {
    final csrfToken = await this.csrfToken();
    if (csrfToken == null) throw Exception("Could not get CSRF token.");
    return csrfToken;
  }

  /// Posts [body] as a form to [path] on RBS, the way a script on [referer]
  /// does.
  Future<http.Response> post(
    String path,
    Map<String, String> body, {
    String referer = searchPage,
    String accept = acceptJson,
  }) {
    return client.post(
      Uri.parse("$base$path"),
      headers: {
        "accept": accept,
        "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
        "x-requested-with": "XMLHttpRequest",
        "referer": referer,
        "origin": base,
      },
      body: body,
    );
  }
}
