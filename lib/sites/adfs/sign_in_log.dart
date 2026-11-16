import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as parser;

/// [url] without its query string or fragment, for logs: sign-in URLs carry
/// tokens and request ids in their query.
String loggableUrl(Uri url) => url.hasAuthority ? '${url.scheme}://${url.host}${url.path}' : url.path;

/// One-line summary of an HTML page for debugging: title, forms with their
/// field names (no values, actions without their query), and, unless
/// [includeText] is false, the start of the visible text.
String describeHtmlPage(String body, {bool includeText = true}) {
  final doc = parser.parse(body);
  final title = doc.querySelector('title')?.text.trim() ?? '';
  final forms = doc.querySelectorAll('form').map((f) {
    final names = f.querySelectorAll('input').map((i) => i.attributes['name']).whereType<String>();
    final action = Uri.tryParse(f.attributes['action'] ?? '');
    return '[${action == null ? '?' : loggableUrl(action)} fields=${names.join(",")}]';
  }).join(' ');
  if (!includeText) return 'title="$title" forms=$forms';
  final text = (doc.body?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return 'title="$title" forms=$forms text="${text.substring(0, text.length.clamp(0, 300))}"';
}

/// Recent sign-in steps from every sign-in (Account, automatic, and other
/// apps' single sign-on such as the timetable), shown in Account → Sign-in
/// details for troubleshooting. Page structure and field names only, never
/// the password; addresses lose their query strings.
class SignInLog extends ValueNotifier<List<String>> {
  /// Lines kept; older ones drop off.
  static const maxLines = 300;

  SignInLog() : super(const []);

  void record(String message) {
    // Error text can carry full addresses (http's ClientException adds
    // "uri=..."): keep the host and path, drop query strings, which can hold
    // tokens or IDs. Users copy this log into bug reports.
    message = message.replaceAllMapped(RegExp(r'(https?://[^\s?#]+)[?#][^\s,)]*'), (m) => '${m[1]}?…');
    final t = DateTime.now();
    final stamp = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    final next = [...value, '$stamp $message'];
    value = next.length > maxLines ? next.sublist(next.length - maxLines) : next;
  }

  /// Forgets every line (the log can name the account).
  void clear() => value = const [];
}
