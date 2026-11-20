// Finding online-class meeting links (Zoom, Teams, Meet, Webex) in
// announcement text, with the meeting ID and passcode written next to them.
// Pure rules: the app never fetches these links, it only offers to open them
// in the browser or meeting app.

import 'package:resit/features/lms/domain/activities.dart';

enum MeetingService {
  zoom('Zoom'),
  teams('Teams'),
  meet('Meet'),
  webex('Webex');

  final String label;
  const MeetingService(this.label);
}

/// A meeting to join, and the ID and passcode written next to it (if any).
class MeetingLink {
  final Uri url;
  final MeetingService service;

  /// e.g. "123 456 7890".
  final String? meetingId;
  final String? passcode;

  const MeetingLink({required this.url, required this.service, this.meetingId, this.passcode});

  @override
  bool operator ==(Object other) =>
      other is MeetingLink &&
      other.url == url &&
      other.service == service &&
      other.meetingId == meetingId &&
      other.passcode == passcode;

  @override
  int get hashCode => Object.hash(url, service, meetingId, passcode);

  @override
  String toString() => 'MeetingLink(${service.label} $url, id: $meetingId, passcode: $passcode)';
}

/// Which meeting service [url] joins, or null if it isn't a meeting link.
/// Only https links on the services' own hosts count: a look-alike host
/// ("zoom.us.example.com", "notzoom.us"), a plain-http link, one with a
/// user name or another port, or a page that isn't a meeting (a recording,
/// the home page) doesn't.
MeetingService? meetingServiceOf(Uri url) {
  if (!url.isScheme('https') || url.userInfo.isNotEmpty) return null;
  if (url.hasPort && url.port != 443) return null;
  final host = url.host.toLowerCase();
  final path = url.path.toLowerCase();
  bool on(String domain) => host == domain || host.endsWith('.$domain');

  if (on('zoom.us')) {
    // Join (j), webinar (w), personal room (my) and web-client links; not
    // the host's start link, recordings or the home page.
    final zoomMeeting = RegExp(r'^/(j|w|my)/[^/]+|^/wc/join/\d+|^/wc/\d+/join');
    return zoomMeeting.hasMatch(path) ? MeetingService.zoom : null;
  }
  if (host == 'teams.microsoft.com' || host == 'teams.live.com') {
    return path.startsWith('/l/meetup-join/') || RegExp(r'^/meet/[^/]+').hasMatch(path) ? MeetingService.teams : null;
  }
  if (host == 'meet.google.com') {
    return RegExp(r'^/([a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[^/]+)/?$').hasMatch(path) ? MeetingService.meet : null;
  }
  if (host.endsWith('.webex.com')) {
    // Personal rooms (/meet/name), meeting links (/site/j.php?MTID=...) and
    // the join service.
    final webexMeeting = RegExp(r'^(/[^/]+)?/(meet|join)/[^/]+|^/[^/]+/j\.php$|^/wbxmjs/joinservice/');
    return webexMeeting.hasMatch(path) ? MeetingService.webex : null;
  }
  return null;
}

/// Outlook's "safe links" wrap a link in their own; the meeting is the
/// address inside.
Uri _unwrap(Uri url) {
  if (url.host.toLowerCase().endsWith('.safelinks.protection.outlook.com')) {
    final inner = Uri.tryParse(url.queryParameters['url'] ?? '');
    if (inner != null) return inner;
  }
  return url;
}

final _anchor = RegExp(
  r'''<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>(.*?)</a\s*>''',
  caseSensitive: false,
  dotAll: true,
);
final _bareUrl = RegExp(r'''https?://[^\s<>"'`]+''', caseSensitive: false);
final _meetingId = RegExp(
  r'(?:meeting\s*(?:id|number)|webinar\s*id|conference\s*id|access\s*code)(?:\s*\([^)]*\))?\s*[:：#]?\s*(\d(?:[\d \-]{6,16})\d)',
  caseSensitive: false,
);
final _passcode = RegExp(
  r'(?:pass\s*code|password|pwd)\s*[:：]\s*(\S+)|(?:pass\s*code|password)\s+is\s+(\S+)',
  caseSensitive: false,
);

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));

/// The announcement as one line of text with each link's address written
/// where the link is, so a link's position can be compared with the
/// "Meeting ID" and "Passcode" around it.
String _linear(String html, String text) {
  if (html.trim().isEmpty) return text;
  final withHrefs = html.replaceAllMapped(_anchor, (m) {
    final href = _decodeEntities((m[1] ?? m[2] ?? m[3] ?? '').trim());
    final label = m[4] ?? '';
    final labelText = _decodeEntities(label.replaceAll(RegExp(r'<[^>]+>'), ''));
    return labelText.contains(href) ? ' $labelText ' : ' $labelText $href ';
  });
  final plain = withHrefs
      .replaceAll(RegExp(r'<(br|/p|/div|/li|/h\d|/tr)\b[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  return _decodeEntities(plain);
}

String _trimUrl(String s) {
  var url = s;
  while (url.isNotEmpty && '.,;:!?)]}\'"'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

String _cleanPasscode(String s) {
  var p = s;
  while (p.isNotEmpty && '.,;)]}\'"'.contains(p[p.length - 1])) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// The meeting links in an announcement, in the order written, each once.
/// [html] is the body as xSiTe stores it (links keep their addresses there,
/// and addresses typed out are in its text); [text], its plain-text
/// version, is read when there's no HTML.
List<MeetingLink> findMeetingLinks({String html = '', String text = ''}) {
  final all = _linear(html, text);

  final found = <({int start, int end, Uri url, MeetingService service})>[];
  for (final m in _bareUrl.allMatches(all)) {
    final raw = _trimUrl(m[0]!);
    final parsed = Uri.tryParse(raw);
    if (parsed == null) continue;
    final url = _unwrap(parsed);
    final service = meetingServiceOf(url);
    if (service == null) continue;
    found.add((start: m.start, end: m.start + raw.length, url: url, service: service));
  }

  final byUrl = <String, MeetingLink>{};
  for (var i = 0; i < found.length; i++) {
    final f = found[i];
    // Details after the link (up to the next one), as invitations write
    // them; for the first link, also before it.
    final afterEnd = i + 1 < found.length ? found[i + 1].start : all.length;
    final after = all.substring(f.end, _min(afterEnd, f.end + 400));
    final before = i == 0 ? all.substring(_max(0, f.start - 300), f.start) : '';

    String? id(String s) => _meetingId.firstMatch(s)?.group(1)?.replaceAll(RegExp(r'[\s-]+'), ' ').trim();
    String? pass(String s) {
      final m = _passcode.firstMatch(s);
      final p = m == null ? null : _cleanPasscode(m[1] ?? m[2] ?? '');
      return p == null || p.isEmpty ? null : p;
    }

    // A Zoom link carries its own number: it wins over a different one in
    // the text (which then belongs to another meeting).
    final fromPath = _zoomIdFromPath(f.url, f.service);
    final written = id(after) ?? id(before);
    final meetingId =
        fromPath != null && written?.replaceAll(' ', '') != fromPath.replaceAll(' ', '') ? fromPath : written;
    final passcode = pass(after) ?? pass(before);
    final key = f.url.toString();
    final kept = byUrl[key];
    byUrl[key] = MeetingLink(
      url: f.url,
      service: f.service,
      meetingId: kept?.meetingId ?? meetingId,
      passcode: kept?.passcode ?? passcode,
    );
  }
  return byUrl.values.toList();
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

/// A Zoom link's meeting number ("/j/1234567890"), spaced as Zoom shows it.
String? _zoomIdFromPath(Uri url, MeetingService service) {
  if (service != MeetingService.zoom) return null;
  final d = RegExp(r'^/(?:j|w|wc/join|wc)/(\d{9,11})(?:/|$)').firstMatch(url.path)?.group(1);
  if (d == null) return null;
  // 123 456 789, 123 456 7890, 123 4567 8901.
  final mid = d.length == 11 ? 7 : 6;
  return '${d.substring(0, 3)} ${d.substring(3, mid)} ${d.substring(mid)}';
}

/// Whether a timetable location means the class is held online.
bool isOnlineLocation(String location) =>
    RegExp(r'\b(online|zoom|ms teams|microsoft teams|webex|google meet|e-?learning)\b', caseSensitive: false)
        .hasMatch(location);

/// The newest meeting link in a course's announcements (the first link of
/// the newest announcement that has one), or null.
MeetingLink? latestMeetingLink(Iterable<Announcement> announcements) {
  Announcement? newest;
  for (final a in announcements) {
    if (a.meetings.isEmpty) continue;
    if (newest == null || (a.date ?? DateTime(0)).isAfter(newest.date ?? DateTime(0))) newest = a;
  }
  return newest?.meetings.first;
}
