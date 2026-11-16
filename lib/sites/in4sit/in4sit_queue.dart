import 'dart:async';

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
