import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/sites/in4sit/in4sit_queue.dart';
import 'package:resit/sites/in4sit/peoplesoft_parsers.dart';
import 'package:resit/core/network/session_client.dart';

// The rest of in4SIT's plumbing lives next to this file; importing this one
// brings in what its readers need.
export 'package:resit/sites/in4sit/in4sit_queue.dart' show In4SitQueue;
export 'package:resit/sites/in4sit/peoplesoft_parsers.dart';

/// in4SIT answered a request with an HTTP error status.
class In4SitHttpException implements Exception {
  final int statusCode;
  const In4SitHttpException(this.statusCode);

  @override
  String toString() => 'in4SIT returned $statusCode.';
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

  /// Drops form fields carried from earlier presses, e.g. a previous grid
  /// row's selection that would otherwise be sent again with the next one.
  void removeFields(bool Function(String name) test) => _form.removeWhere((name, _) => test(name));
}
