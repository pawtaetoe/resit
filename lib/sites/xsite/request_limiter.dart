import 'dart:async';
import 'dart:collection';

/// Lets at most [max] tasks run at once; the rest wait their turn.
class RequestLimiter {
  final int max;
  var _running = 0;
  final _waiting = Queue<Completer<void>>();

  RequestLimiter(this.max);

  Future<T> call<T>(Future<T> Function() task) async {
    if (_running >= max) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      // Hand the slot straight to the next in line, or free it.
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
