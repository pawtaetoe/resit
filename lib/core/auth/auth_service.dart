import 'package:html/parser.dart' as parser;
import 'package:resit/core/network/session_client.dart';

class AuthService {
  final SessionClient client;

  AuthService(this.client);

  static const String base = "https://rbs.singaporetech.edu.sg";
  static const String callback = "$base/Account/LoginCallbak";
  static const String protected = "$base/SRB001/SRB001Page";

  String? _cachedCsrfToken;

  Future<bool> login(String username, String password) async {
    client.clearCookies();
    _cachedCsrfToken = null;

    // 1. GET the protected page. This redirects to ADFS.
    print('--- ADFS Login Started ---');
    var response = await client.get(Uri.parse(protected));
    print('Step 1 (GET protected page): Status ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch protected page.');
    }

    // The response URL is now the ADFS login form URL.
    var adfsUrl = response.request?.url;
    if (adfsUrl == null) throw Exception('No redirect to ADFS login page.');

    // 2. POST credentials to ADFS
    var loginResponse = await client.post(
      adfsUrl,
      body: {
        "UserName": "$username@sit.singaporetech.edu.sg",
        "Password": password,
        "AuthMethod": "FormAuthentication",
      },
    );
    print('Step 2 (POST credentials): Status ${loginResponse.statusCode}');
    if (loginResponse.statusCode != 200) {
      throw Exception('Failed to post credentials to ADFS. Body: ${loginResponse.body.substring(0, 100)}...');
    }

    // 3. Replay the ADFS relay form to the callback
    var document = parser.parse(loginResponse.body);
    var hiddenInputs = document.querySelectorAll('input[type="hidden"]');
    
    Map<String, String> fields = {};
    for (var input in hiddenInputs) {
      var name = input.attributes['name'];
      var value = input.attributes['value'];
      if (name != null && value != null) {
        if (['wa', 'wresult', 'wctx'].contains(name.toLowerCase())) {
          fields[name] = value;
        }
      }
    }

    if (!fields.containsKey('wresult')) {
      throw Exception("No wresult found in ADFS reply. Check your Student ID and Password.");
    }

    print('Step 3 (Replay form to callback): POSTing ${fields.keys.join(", ")}');
    var callbackResponse = await client.post(
      Uri.parse(callback),
      body: fields,
    );
    print('Step 3 Result: Status ${callbackResponse.statusCode}, URL: ${callbackResponse.request?.url}');
    
    // Use a small reflection-like hack to print cookies since they are private in SessionClient.
    // We can just trust the hasAuthCookie, but let's print the headers sent and received.
    print('Step 3 Response Headers: ${callbackResponse.headers}');

    if (callbackResponse.statusCode != 200 && callbackResponse.statusCode != 302) {
       print('Warning: Unexpected status code from callback: ${callbackResponse.statusCode}');
    }

    final hasCookie = client.hasAuthCookie();
    print('Final Check: hasAuthCookie = $hasCookie');
    return hasCookie;
  }

  Future<String?> getCsrfToken() async {
    if (_cachedCsrfToken != null) return _cachedCsrfToken;

    final response = await client.get(Uri.parse(protected));
    print('CSRF fetch status: ${response.statusCode}, URL: ${response.request?.url}');

    if (response.statusCode >= 400) {
      print('Error: Failed to fetch protected page for CSRF.');
      return null;
    }

    final doc = parser.parse(response.body);
    final input = doc.querySelector('input[name="__RequestVerificationToken"]');
    final token = input?.attributes['value'];

    if (token == null || token.isEmpty) {
      // Also try a meta tag (some apps expose it that way)
      final meta = doc.querySelector('meta[name="csrf-token"], meta[name="__RequestVerificationToken"]');
      final metaToken = meta?.attributes['content'];
      if (metaToken != null && metaToken.isNotEmpty) {
        _cachedCsrfToken = metaToken;
        return metaToken;
      }

      print('CRITICAL: No CSRF token in HTML. First 800 chars:');
      print(response.body.substring(0, response.body.length.clamp(0, 800)));
      return null;
    }

    _cachedCsrfToken = token;
    return token;
  }
}

