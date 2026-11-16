import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

// Reading PeopleSoft's replies: unwrapping its AJAX XML, collecting the form
// fields a browser would send back, and small helpers for its markup. Pure,
// so they can run on a background isolate.

/// Reads what a caller needs from a parsed PeopleSoft reply. [html] is the
/// unwrapped HTML the document was parsed from. Must be a top-level or
/// static function returning plain data, as it may run on another isolate.
typedef PeopleSoftReader<T> = T Function(dom.Document doc, String html);

/// A PeopleSoft reply, parsed once: the form fields it carries, the
/// server's state counter, and what the caller's reader took from it.
class PeopleSoftReply<T> {
  final Map<String, String> fields;
  final String? stateNum;
  final T data;

  const PeopleSoftReply(this.fields, this.stateNum, this.data);
}

/// Unwraps, parses and reads a PeopleSoft reply in one pass. [formOnly]
/// takes the fields from the page's main form (a full page load) rather
/// than the whole reply (an AJAX update). Pure, so it can run on an isolate.
PeopleSoftReply<T> readPeopleSoftReply<T>((String body, bool formOnly, PeopleSoftReader<T> read) args) {
  final (body, formOnly, read) = args;
  final html = unwrapPeopleSoft(body);
  final doc = parser.parse(html);
  final fields = <String, String>{};
  final scope = formOnly
      ? (doc.querySelector('form[name="win0"]') ?? doc.querySelector('form#win0') ?? doc.documentElement!)
      : doc.documentElement!;
  readPeopleSoftInputs(scope, fields);
  final state = RegExp(r'ICStateNum\.value\s*=\s*(\d+)').firstMatch(body)?.group(1);
  return PeopleSoftReply<T>(fields, state, read(doc, html));
}

/// Collects what a browser would submit for the inputs in [scope] into
/// [fields].
void readPeopleSoftInputs(dom.Element scope, Map<String, String> fields) {
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

final _cdataField = RegExp(r'<FIELD\b[^>]*><!\[CDATA\[(.*?)\]\]></FIELD>', dotAll: true, caseSensitive: false);

/// PeopleSoft answers AJAX requests with XML whose <FIELD> elements wrap the
/// real HTML in CDATA; a normal page load is plain HTML. Returns the HTML.
String unwrapPeopleSoft(String body) {
  if (!body.contains('<![CDATA[')) return body;
  final buf = StringBuffer();
  for (final m in _cdataField.allMatches(body)) {
    buf.write(m.group(1));
  }
  return buf.isEmpty ? body : buf.toString();
}

/// Visible text of an element, with whitespace and &nbsp; collapsed.
String cellText(dom.Element el) => el.text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Elements by exact id. PeopleSoft ids contain `$` (e.g. `N_XM_RSLT_WRK_DESCR$0`),
/// which the html package's getElementById can't look up, so this matches the
/// attribute directly.
Map<String, dom.Element> elementsById(dom.Document doc) => {
      for (final el in doc.querySelectorAll('[id]')) el.attributes['id']!: el,
    };
