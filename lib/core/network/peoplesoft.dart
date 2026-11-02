import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';

/// A stateful in4SIT (PeopleSoft) page: opened through ADFS single sign-on,
/// then driven by "pressing" its buttons with AJAX posts that carry the
/// page's form state forward, as the browser does.
class PeopleSoftPage {
  final AuthService auth;
  final Uri url;

  Map<String, String> _form = {};
  bool _open = false;

  PeopleSoftPage(this.auth, this.url);

  bool get isOpen => _open;

  /// Loads the page (signing in through ADFS if needed) and returns its
  /// HTML. Throws [SessionExpiredException] if single sign-on couldn't get
  /// through to the page.
  Future<String> open({void Function(MfaChallenge)? onMfaChallenge}) async {
    _open = false;
    _form = {};
    final response = await auth.getWithSso(url, onMfaChallenge: onMfaChallenge);
    final landed = response.request?.url;
    if (landed != null && landed.host != url.host) {
      final doc = parser.parse(response.body);
      final title = doc.querySelector('title')?.text.trim() ?? '';
      final hasPassword = doc.querySelector('input[type="password"]') != null;
      throw SessionExpiredException('Landed on ${landed.host}${landed.path}'
          '${title.isNotEmpty ? ' ("$title")' : ''}'
          '${hasPassword ? ', which is asking for a password' : ''}.');
    }
    if (response.statusCode >= 400) throw Exception('in4SIT returned ${response.statusCode}.');

    final doc = parser.parse(unwrapPeopleSoft(response.body));
    final form = doc.querySelector('form[name="win0"]') ?? doc.querySelector('form#win0');
    _readInputs(form ?? doc.documentElement!, _form);
    _form['ICAction'] = 'None';
    _open = true;
    return response.body;
  }

  /// Presses [action] (a button or link id) with [fields] set, e.g. a grid
  /// row's radio button, and returns the response. The page's state moves
  /// forward with it.
  Future<String> press(String action, {Map<String, String> fields = const {}}) async {
    if (!_open) throw StateError('Open the page first.');
    final body = Map<String, String>.from(_form)
      ..addAll(fields)
      ..['ICAJAX'] = '1'
      ..['ICNAVTYPEDROPDOWN'] = '0'
      ..['ICChanged'] = '1'
      ..['ICAction'] = action;

    final response = await auth.client.post(
      url,
      headers: {
        'x-requested-with': 'XMLHttpRequest',
        'referer': url.toString(),
        'origin': '${url.scheme}://${url.host}',
      },
      body: body,
    );
    debugLog('PeopleSoft ${url.pathSegments.last} $action: status ${response.statusCode}, '
        '${response.body.length} chars');
    if (response.statusCode != 200) {
      _open = false;
      throw Exception('in4SIT returned ${response.statusCode}.');
    }

    _form.addAll(fields);
    _absorb(response.body);
    return response.body;
  }

  /// Carries the page state forward: new field values and the server's state
  /// counter, which must match on the next request.
  void _absorb(String body) {
    final doc = parser.parse(unwrapPeopleSoft(body));
    _readInputs(doc.documentElement!, _form);
    final state = RegExp(r'ICStateNum\.value\s*=\s*(\d+)').firstMatch(body);
    _form['ICStateNum'] = state?.group(1) ?? '${(int.tryParse(_form['ICStateNum'] ?? '') ?? 0) + 1}';
    _form['ICAction'] = 'None';
    _form['ICResubmit'] = '0';
  }

  static void _readInputs(dom.Element scope, Map<String, String> fields) {
    for (final el in scope.querySelectorAll('input, select, textarea')) {
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;
      if (el.localName == 'select') {
        final selected = el.querySelector('option[selected]') ?? el.querySelector('option');
        fields[name] = selected?.attributes['value'] ?? selected?.text ?? '';
      } else if (el.localName == 'textarea') {
        fields[name] = el.text;
      } else {
        switch ((el.attributes['type'] ?? 'text').toLowerCase()) {
          case 'button' || 'submit' || 'image' || 'reset':
            break;
          case 'checkbox':
            if (el.attributes.containsKey('checked')) {
              fields[name] = el.attributes['value'] ?? 'on';
            } else {
              fields.remove(name);
            }
          case 'radio':
            if (el.attributes.containsKey('checked')) fields[name] = el.attributes['value'] ?? '';
          default:
            fields[name] = el.attributes['value'] ?? '';
        }
      }
    }
  }
}

/// PeopleSoft answers AJAX requests with XML whose <FIELD> elements wrap the
/// real HTML in CDATA; a normal page load is plain HTML. Returns the HTML.
String unwrapPeopleSoft(String body) {
  if (!body.contains('<![CDATA[')) return body;
  final buf = StringBuffer();
  final re = RegExp(r'<FIELD\b[^>]*><!\[CDATA\[(.*?)\]\]></FIELD>', dotAll: true, caseSensitive: false);
  for (final m in re.allMatches(body)) {
    buf.write(m.group(1));
  }
  return buf.isEmpty ? body : buf.toString();
}

/// Visible text of an element, with whitespace and &nbsp; collapsed.
String cellText(dom.Element el) => el.text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Elements by exact id. PeopleSoft ids contain `$` (e.g. `N_XM_RSLT_WRK_DESCR$0`),
/// which the html package's getElementById can't look up, so this matches the
/// attribute directly.
Map<String, dom.Element> elementsById(dom.Document doc) => {
      for (final el in doc.querySelectorAll('[id]')) el.attributes['id']!: el,
    };
