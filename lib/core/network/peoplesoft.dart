import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/network/session_client.dart';

/// One queue for every in4SIT (PeopleSoft) request the app makes.
///
/// in4SIT keeps one page's state per sign-in: opening another in4SIT page
/// drops the state of the page opened before it. So the timetable and the
/// exam results must take turns, never interleave requests, and each must
/// know when the other has opened a page in the meantime ([holds]).
class In4SitQueue {
  Future<void> _tail = Future.value();
  Object? _holder;

  /// Runs [task] after every task queued before it. A task must not queue
  /// another task and wait for it (that would wait forever).
  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  /// Records that [page] was just opened, so in4SIT now holds its state and
  /// no longer that of whichever page was opened before.
  void claim(Object page) => _holder = page;

  /// Whether [page] is still the last in4SIT page opened.
  bool holds(Object page) => identical(_holder, page);

  /// Forgets [page] if it was the last opened (e.g. its state was lost).
  void release(Object page) {
    if (identical(_holder, page)) _holder = null;
  }
}

/// in4SIT answered a request with an HTTP error status.
class In4SitHttpException implements Exception {
  final int statusCode;
  const In4SitHttpException(this.statusCode);

  @override
  String toString() => 'in4SIT returned $statusCode.';
}

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

/// Replies at least this long are parsed on a background isolate; shorter
/// ones aren't worth the hand-off.
@visibleForTesting
int offThreadParseThreshold = 32 * 1024;

/// Runs [fn] on [arg] off the UI thread (with [compute]) when [size] is at
/// least [offThreadParseThreshold], otherwise right here. [fn] must be a
/// top-level or static function and [arg]/the result plain data.
Future<R> parseOffThread<A, R>(R Function(A) fn, A arg, {required int size, String? label}) async {
  if (size < offThreadParseThreshold) return fn(arg);
  return compute(fn, arg, debugLabel: label);
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

Null _readNothing(dom.Document doc, String html) => null;

/// A stateful in4SIT (PeopleSoft) page: opened through ADFS single sign-on,
/// then driven by "pressing" its buttons with AJAX posts that carry the
/// page's form state forward, as the browser does.
///
/// Requests made through a page are not queued by the page itself: run them
/// inside [In4SitQueue.run]. Pass the [queue] so opening this page is
/// recorded there (see [In4SitQueue.holds]).
class PeopleSoftPage {
  final AuthService auth;
  final Uri url;
  final In4SitQueue? queue;

  Map<String, String> _form = {};
  bool _open = false;

  PeopleSoftPage(this.auth, this.url, {this.queue});

  /// Whether the page is open and, when it has a [queue], still the last
  /// in4SIT page opened (so in4SIT still has its state).
  bool get isOpen => _open && (queue?.holds(this) ?? true);

  /// Forgets the page's state; the next use must [open] it again.
  void close() {
    _open = false;
    _form = {};
    queue?.release(this);
  }

  /// Loads the page (signing in through ADFS if needed) and returns its
  /// HTML. Throws [SessionExpiredException] if single sign-on couldn't get
  /// through to the page.
  Future<String> open({void Function(MfaChallenge)? onMfaChallenge}) async =>
      (await openWith<Null>(_readNothing, onMfaChallenge: onMfaChallenge)).body;

  /// Like [open], and also returns what [read] takes from the page, parsed
  /// once (off the UI thread for big pages).
  Future<({String body, T data})> openWith<T>(PeopleSoftReader<T> read,
      {void Function(MfaChallenge)? onMfaChallenge}) async {
    close();
    final response = await auth.getWithSso(url, onMfaChallenge: onMfaChallenge);
    final body = response.body; // decoded once
    final landed = response.request?.url;
    if (landed != null && landed.host != url.host) {
      final doc = parser.parse(body);
      final title = doc.querySelector('title')?.text.trim() ?? '';
      final hasPassword = doc.querySelector('input[type="password"]') != null;
      throw SessionExpiredException('Landed on ${landed.host}${landed.path}'
          '${title.isNotEmpty ? ' ("$title")' : ''}'
          '${hasPassword ? ', which is asking for a password' : ''}.');
    }
    if (response.statusCode >= 400) throw In4SitHttpException(response.statusCode);

    final reply = await parseOffThread(readPeopleSoftReply<T>, (body, true, read),
        size: body.length, label: 'in4SIT ${url.pathSegments.last}');
    _form = reply.fields..['ICAction'] = 'None';
    _open = true;
    queue?.claim(this);
    return (body: body, data: reply.data);
  }

  /// Presses [action] (a button or link id) with [fields] set, e.g. a grid
  /// row's radio button, and returns the response. The page's state moves
  /// forward with it.
  Future<String> press(String action, {Map<String, String> fields = const {}}) async =>
      (await pressWith<Null>(action, _readNothing, fields: fields)).body;

  /// Like [press], and also returns what [read] takes from the reply, parsed
  /// once (off the UI thread for big replies).
  Future<({String body, T data})> pressWith<T>(String action, PeopleSoftReader<T> read,
      {Map<String, String> fields = const {}}) async {
    if (!_open) throw StateError('Open the page first.');
    final request = Map<String, String>.from(_form)
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
      body: request,
    );
    final body = response.body; // decoded once
    debugLog('PeopleSoft ${url.pathSegments.last} $action: status ${response.statusCode}, ${body.length} chars');
    if (response.statusCode != 200) {
      close();
      throw In4SitHttpException(response.statusCode);
    }

    final reply = await parseOffThread(readPeopleSoftReply<T>, (body, false, read),
        size: body.length, label: 'in4SIT $action');
    // Carry the page state forward: new field values and the server's state
    // counter, which must match on the next request.
    _form
      ..addAll(fields)
      ..addAll(reply.fields)
      ..['ICStateNum'] = reply.stateNum ?? '${(int.tryParse(_form['ICStateNum'] ?? '') ?? 0) + 1}'
      ..['ICAction'] = 'None'
      ..['ICResubmit'] = '0';
    return (body: body, data: reply.data);
  }

  /// Sets a form field for the next [press] without sending anything.
  void setField(String name, String value) => _form[name] = value;
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
