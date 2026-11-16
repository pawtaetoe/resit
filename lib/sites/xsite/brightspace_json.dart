// The parts of Brightspace's replies every xSiTe parser reads the same way:
// the anti-script guard before JSON, and rich-text blocks.

/// Some Brightspace APIs put `while(1);` before JSON so it can't be loaded as
/// a script; drop it if present.
String stripGuard(String body) {
  final t = body.trimLeft();
  return t.startsWith('while(1);') ? t.substring('while(1);'.length) : t;
}

/// Plain text of a Brightspace rich-text block ({Text, Html}), or of a bare
/// string.
String richText(Object? v) {
  if (v is String) return v.trim();
  if (v is Map) {
    final text = v['Text'];
    if (text is String && text.trim().isNotEmpty) return text.trim();
    // Some blocks nest the text one level down: {Text: {Text, Html}}.
    if (text is Map) return richText(text);
    final html = v['Html'];
    if (html is String) return htmlToText(html);
  }
  return '';
}

/// Rough plain text from HTML: tags dropped, common entities decoded,
/// paragraphs kept apart.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(br|/p|/div|/li|/h\d)\b[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {'&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'"};
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));
  return s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n\s*(\n\s*)+'), '\n\n').trim();
}
