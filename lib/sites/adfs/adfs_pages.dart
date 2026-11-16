import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

// Reading SIT's ADFS sign-in pages: the relay form that carries the sign-in
// token, MFA pages, error messages and the fields a browser would submit.
// Pure functions of the HTML, so they're tested on saved pages.

/// ADFS answered a password with its password form again: the password
/// was turned down.
bool asksForPassword(String page) => parser.parse(page).querySelector('form input[type="password"]') != null;

({Uri action, Map<String, String> fields})? extractRelayForm(String body, Uri pageUrl) {
  final doc = parser.parse(body);
  for (final form in doc.querySelectorAll('form')) {
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name != null && name.isNotEmpty) fields[name] = input.attributes['value'] ?? '';
    }
    final keys = fields.keys.map((k) => k.toLowerCase());
    if (keys.contains('wresult') || keys.contains('samlresponse')) {
      final action = form.attributes['action'];
      return (
        action: (action == null || action.isEmpty) ? pageUrl : pageUrl.resolve(action),
        fields: fields,
      );
    }
  }
  return null;
}

String? extractCsrf(String body) {
  final doc = parser.parse(body);
  final input = doc.querySelector('input[name="__RequestVerificationToken"]');
  final token = input?.attributes['value'];
  if (token != null && token.isNotEmpty) return token;

  // Some apps expose it as a meta tag instead
  final meta = doc.querySelector('meta[name="csrf-token"], meta[name="__RequestVerificationToken"]');
  final metaToken = meta?.attributes['content'];
  if (metaToken != null && metaToken.isNotEmpty) return metaToken;
  return null;
}

Map<String, String>? extractRelayFields(String body) {
  final document = parser.parse(body);
  final fields = <String, String>{};
  for (final input in document.querySelectorAll('input[type="hidden"]')) {
    final name = input.attributes['name'];
    final value = input.attributes['value'];
    if (name != null && value != null && ['wa', 'wresult', 'wctx'].contains(name.toLowerCase())) {
      fields[name] = value;
    }
  }
  return fields.containsKey('wresult') ? fields : null;
}

/// An ADFS MFA page: no password box, and a form carrying ADFS's
/// AuthMethod/Context fields. Stricter than [isMfaPage], which only runs
/// right after a password was submitted.
bool isAdfsMfaPage(dom.Document doc) {
  if (doc.querySelector('input[type="password"]') != null) return false;
  return doc.querySelector('form input[name="AuthMethod"], form input[name="Context"]') != null;
}

/// A page that is not the relay form, has no password box (so it is not
/// the login form re-rendered after a bad password) but does have a form.
bool isMfaPage(String body) {
  final doc = parser.parse(body);
  if (doc.querySelector('input[type="password"]') != null) return false;
  return pickForm(doc) != null;
}

dom.Element? pickForm(dom.Document doc) {
  final forms = doc.querySelectorAll('form');
  if (forms.isEmpty) return null;
  return forms.firstWhere(
    (f) => f.querySelector('input[name="AuthMethod"], input[name="Context"]') != null,
    orElse: () => forms.first,
  );
}

/// Collects what a browser would submit for [form]: hidden/text inputs,
/// checked boxes/radios, the Authenticator-ish radio if none is checked, and
/// the first named submit button.
Map<String, String> formFields(dom.Element form, {bool preferCode = false}) {
  final fields = <String, String>{};
  final radios = <String, List<dom.Element>>{};
  String? submitName;
  String? submitValue;

  for (final input in form.querySelectorAll('input, select, textarea')) {
    final name = input.attributes['name'];
    if (name == null || name.isEmpty) continue;
    final type = (input.attributes['type'] ?? 'text').toLowerCase();

    switch (type) {
      case 'submit':
      case 'button':
      case 'image':
        if (submitName == null) {
          submitName = name;
          submitValue = input.attributes['value'] ?? '';
        }
      case 'checkbox':
        if (input.attributes.containsKey('checked')) {
          fields[name] = input.attributes['value'] ?? 'on';
        }
      case 'radio':
        radios.putIfAbsent(name, () => []).add(input);
      default:
        fields[name] = input.attributes['value'] ?? '';
    }
  }

  radios.forEach((name, group) {
    final checked = group.where((r) => r.attributes.containsKey('checked'));
    final preferred = group.where((r) => RegExp(r'authenticator|notification|approve|push', caseSensitive: false)
        .hasMatch('${r.attributes['value']} ${r.parent?.text ?? ''}'));
    final codeOption = group.where((r) => RegExp(r'code|otp|otc|verification|token|passcode', caseSensitive: false)
        .hasMatch('${r.attributes['value']} ${r.parent?.text ?? ''}'));
    final pick = preferCode && codeOption.isNotEmpty
        ? codeOption.first
        : checked.isNotEmpty
            ? checked.first
            : preferred.isNotEmpty
                ? preferred.first
                : group.first;
    fields[name] = pick.attributes['value'] ?? '';
  });

  if (submitName != null) fields[submitName] = submitValue ?? '';
  return fields;
}

String? extractMfaNumber(dom.Document doc) {
  // An element that is just the number (id/class mentions number or code)
  for (final el in doc.querySelectorAll('[id*="umber"], [class*="umber"], [id*="ode"], [class*="ode"]')) {
    final text = el.text.trim();
    if (RegExp(r'^\d{2,3}$').hasMatch(text)) return text;
  }
  // "... enter the number 57 ..." in the page text
  final text = doc.body?.text.replaceAll(RegExp(r'\s+'), ' ') ?? '';
  final match = RegExp(r'number\D{0,40}?(\d{2,3})\b', caseSensitive: false).firstMatch(text);
  return match?.group(1);
}

/// The error message an ADFS page shows, or null. ADFS fills its error box
/// from a script after the page loads (`delayPopulate('errorText', "...")`),
/// so that is read first; the "View details" link that sits in a box styled
/// as an error is never taken for the message.
String? extractError(dom.Document doc) {
  final scripted =
      RegExp(r"""[dD]elayPopulate\(\s*['"]errorText['"]\s*,\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')""");
  for (final script in doc.querySelectorAll('script')) {
    for (final m in scripted.allMatches(script.text)) {
      final text = (m.group(1) ?? m.group(2) ?? '').replaceAll(r'\"', '"').replaceAll(r"\'", "'").trim();
      if (text.isNotEmpty) return text;
    }
  }

  for (final el in doc.querySelectorAll('#errorText, #error, .error, .error-text, [id*="rror"]')) {
    if (el.id == 'detailsDiv' || el.querySelector('#viewDetailsLink') != null) continue;
    final text = el.text.trim();
    if (text.isNotEmpty && text != 'View details') return text;
  }
  return null;
}

/// The form and box on an MFA page that want a one-time code, searching
/// every form (the code box isn't always in the form [pickForm] chooses).
({dom.Element form, String name})? findCodeForm(dom.Document doc) {
  for (final form in doc.querySelectorAll('form')) {
    final name = findCodeInput(form);
    if (name != null) return (form: form, name: name);
  }
  return null;
}

/// The name of the box in [form] that wants a one-time code, or null.
/// Matched by name/id/autocomplete since ADFS adapters name it differently
/// (e.g. VerificationCode, otc, Passcode), then by code-like hints (numeric
/// keyboard, 6-8 character limit), and finally, on a form with exactly one
/// visible text box and no password box, that box.
String? findCodeInput(dom.Element form) {
  final pattern = RegExp(r'code|otp|otc|token|verification|passcode|pin', caseSensitive: false);
  final visible = <dom.Element>[];
  for (final input in form.querySelectorAll('input')) {
    final name = input.attributes['name'];
    if (name == null || name.isEmpty) continue;
    final type = (input.attributes['type'] ?? 'text').toLowerCase();
    if (!const {'text', 'tel', 'number', 'password'}.contains(type)) continue;
    final hints = '${input.attributes['autocomplete'] ?? ''} $name ${input.attributes['id'] ?? ''} '
        '${input.attributes['placeholder'] ?? ''} ${input.attributes['aria-label'] ?? ''}';
    if (hints.contains('one-time-code') || pattern.hasMatch(hints)) return name;
    if (type != 'password') visible.add(input);
  }

  for (final input in visible) {
    final numeric = (input.attributes['inputmode'] ?? '').toLowerCase() == 'numeric' ||
        (input.attributes['type'] ?? '').toLowerCase() == 'tel' ||
        (input.attributes['type'] ?? '').toLowerCase() == 'number' ||
        (input.attributes['pattern'] ?? '').contains(r'\d');
    final maxLength = int.tryParse(input.attributes['maxlength'] ?? '');
    if (numeric || (maxLength != null && maxLength >= 6 && maxLength <= 8)) return input.attributes['name'];
  }

  final hasPassword = form.querySelector('input[type="password"]') != null;
  if (visible.length == 1 && !hasPassword) return visible.single.attributes['name'];
  return null;
}

/// Debug summary of an MFA page: the names (never the values, which hold
/// the user name and sign-in context) of the fields to submit, the visible
/// boxes, and the sign-in method choices offered.
String describeMfaPage(dom.Document doc, Map<String, String> fields) {
  final names = fields.keys.join(',');
  final inputs = doc
      .querySelectorAll('input')
      .where((i) => (i.attributes['type'] ?? 'text').toLowerCase() != 'hidden')
      .map((i) => '${i.attributes['name'] ?? i.attributes['id'] ?? '?'}(${i.attributes['type'] ?? 'text'}'
          '${i.attributes['autocomplete'] != null ? ',${i.attributes['autocomplete']}' : ''})')
      .join(' ');
  final choices = doc
      .querySelectorAll('a, button, label')
      .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((t) =>
          RegExp(r'another way|other|code|verification|authenticator|text|call', caseSensitive: false).hasMatch(t))
      .where((t) => t.length < 80)
      .take(6)
      .join(' / ');
  return 'fields: $names | inputs: $inputs | choices: $choices';
}
