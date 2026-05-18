import 'package:html/parser.dart' as parser;
import 'package:resit/core/network/session_client.dart';

class AuthService {
  final SessionClient client;

  AuthService(this.client);

  static const String base = "https://in4sit.singaporetech.edu.sg/";
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

    try {
      print('Fetching CSRF token from $protected...');
      var response = await client.get(Uri.parse(protected));
      print('CSRF fetch status: ${response.statusCode}, URL: ${response.request?.url}');
      
      if (response.statusCode != 200) {
        print('Error: Failed to fetch protected page for CSRF.');
        return null;
      }

      final regex = RegExp(r'name="__RequestVerificationToken"[^>]*value="([^"]+)"');
      final match = regex.firstMatch(response.body);
      
      if (match != null && match.groupCount >= 1) {
        _cachedCsrfToken = match.group(1);
        return _cachedCsrfToken;
      }
      
      print('CRITICAL: Could not find CSRF token in the HTML! First 500 chars of body:');
      print(response.body.substring(0, response.body.length < 500 ? response.body.length : 500));
      return null;
    } catch (e) {
      print('CSRF error: $e');
      return null;
    }
  }
}

