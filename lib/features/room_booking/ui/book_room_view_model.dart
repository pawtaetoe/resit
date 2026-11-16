import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/room_booking/data/last_room_search.dart';
import 'package:resit/features/room_booking/domain/booking_hours.dart';
import 'package:resit/features/room_booking/domain/quota.dart';
import 'package:resit/features/room_booking/domain/rooms.dart';
import 'package:resit/features/room_booking/room_booking_providers.dart';

/// What the Book a room screen shows: the slot being searched for, the room
/// type filter and the search's results.
@immutable
class BookRoomState {
  /// The day, start time (minutes since midnight) and length (minutes).
  final DateTime date;
  final int startMin;
  final int duration;

  final bool searching;

  /// Rooms free for the whole slot; null before a search.
  final List<RoomWithSlots>? rooms;

  /// Progress of the per-room search, and rooms that couldn't be checked.
  final int checked;
  final int total;
  final List<Room> failed;

  /// Why the search failed, and whether it was signing in that failed.
  final String? error;
  final bool errorIsSession;

  /// Every room the school lists, and the room types picked in the filter.
  /// Discussion and meeting rooms are picked by default.
  final List<Room>? allRooms;
  final Set<String> types;
  final bool loadingRooms;
  final String? roomsError;

  /// The room type filter starts collapsed to a one-line summary.
  final bool typesExpanded;

  /// The text the results are filtered by.
  final String filter;

  /// The user stopped the last search.
  final bool stopped;

  const BookRoomState({
    required this.date,
    required this.startMin,
    required this.duration,
    required this.searching,
    required this.rooms,
    required this.checked,
    required this.total,
    required this.failed,
    required this.error,
    required this.errorIsSession,
    required this.allRooms,
    required this.types,
    required this.loadingRooms,
    required this.roomsError,
    required this.typesExpanded,
    required this.filter,
    required this.stopped,
  });

  int get endMin => startMin + duration;

  /// [date] the way RBS takes it.
  String get apiDate => DateFormat('d MMM yyyy').format(date);

  String get slotSummary => '${DateFormat('EEE d MMM').format(date)} · ${hhmm(startMin)} – ${hhmm(endMin)}';

  /// The start times still open on [date].
  List<int> get startTimes => startOptions(date, DateTime.now());

  /// The lengths that end by closing time.
  List<int> get lengths => validDurations(startMin);

  /// Whether every picked room type has a weekly allowance; only then do the
  /// hours left limit the length that can be picked.
  bool get onlyQuotaTypes => types.isNotEmpty && types.every((t) => canonicalRoomType(t) != null);
}

/// The Book a room screen's view model. Each screen gets its own: the screen
/// scopes this provider (see `DashboardScreen`).
final bookRoomProvider =
    NotifierProvider.autoDispose<BookRoomViewModel, BookRoomState>(BookRoomViewModel.new);

/// Searches every room of the picked types for the picked slot, one room
/// per request, listing free rooms as answers arrive.
class BookRoomViewModel extends AutoDisposeNotifier<BookRoomState> {
  late DateTime _date;
  late int _startMin;
  int _duration = 120;

  bool _searching = false;
  List<RoomWithSlots>? _rooms;

  /// Progress of the per-room search, and rooms that couldn't be checked.
  int _checked = 0;
  int _total = 0;
  List<Room> _failed = [];
  Object? _firstFailure;
  StreamSubscription<RoomCheck>? _searchSub;

  /// Room results arrive many per second; the screen redraws for them at
  /// most every 80 ms instead of once per room.
  Timer? _redraw;
  void _scheduleRedraw() {
    _redraw ??= Timer(const Duration(milliseconds: 80), () {
      _redraw = null;
      _publish();
    });
  }

  String? _error;
  bool _errorIsSession = false;

  List<Room>? _allRooms;
  Set<String> _types = {};
  bool _loadingRooms = false;
  String? _roomsError;

  bool _typesExpanded = false;
  String _filter = '';

  /// Room types from the last search, applied once the room list loads.
  Set<String>? _savedTypes;

  /// Completes when the running search ends, including when it's stopped.
  Completer<void>? _searchDone;
  bool _stopped = false;

  bool _disposed = false;

  @override
  BookRoomState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancelSearch();
      _redraw?.cancel();
    });
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final earliest = earliestStart(today, now);
    if (earliest == null) {
      // Too late to book today: start on tomorrow.
      _date = today.add(const Duration(days: 1));
      _startMin = 9 * 60;
    } else {
      _date = today;
      _startMin = earliest < 13 * 60 ? 13 * 60 : earliest;
    }
    _duration = validDurations(_startMin).contains(120) ? 120 : validDurations(_startMin).last;
    Future.microtask(_start);
    return _snapshot();
  }

  BookRoomState _snapshot() => BookRoomState(
        date: _date,
        startMin: _startMin,
        duration: _duration,
        searching: _searching,
        rooms: _rooms == null ? null : List.unmodifiable(_rooms!),
        checked: _checked,
        total: _total,
        failed: List.unmodifiable(_failed),
        error: _error,
        errorIsSession: _errorIsSession,
        allRooms: _allRooms,
        types: Set.unmodifiable(_types),
        loadingRooms: _loadingRooms,
        roomsError: _roomsError,
        typesExpanded: _typesExpanded,
        filter: _filter,
        stopped: _stopped,
      );

  /// Shows the latest values on screen.
  void _publish() {
    if (!_disposed) state = _snapshot();
  }

  Future<void> _start() async {
    if (_disposed) return;
    await _loadPrefs();
    if (!_disposed) loadRooms();
  }

  /// Restores the last search's length, start time and room types, where
  /// they're still valid, so a regular booking takes fewer taps.
  Future<void> _loadPrefs() async {
    final saved = await loadLastRoomSearch();
    if (saved == null || _disposed) return;
    final (:duration, :start, :types) = saved;
    if (start != null && startOptions(_date, DateTime.now()).contains(start)) _startMin = start;
    if (duration != null && validDurations(_startMin).contains(duration)) _duration = duration;
    if (types != null && types.isNotEmpty) _savedTypes = types.toSet();
    _publish();
  }

  void _savePrefs() => saveLastRoomSearch(duration: _duration, start: _startMin, types: _types);

  /// Stops a running search; rooms found so far stay listed.
  void stopSearch() => _cancelSearch(stoppedByUser: true);

  void _cancelSearch({bool stoppedByUser = false}) {
    _searchSub?.cancel();
    _searchSub = null;
    final done = _searchDone;
    if (done != null && !done.isCompleted) done.complete();
    if (stoppedByUser) {
      _stopped = true;
      _publish();
    }
  }

  /// Loads the room list so the type filter can show every type there is.
  Future<List<Room>> loadRooms() async {
    final cached = _allRooms;
    if (cached != null) return cached;
    _loadingRooms = true;
    _roomsError = null;
    _publish();
    try {
      final rooms = await ref.read(bookingServiceProvider).getRooms();
      if (!_disposed) {
        _allRooms = rooms;
        final types = rooms.map((r) => r.rsrcTypName).where((t) => t.isNotEmpty).toSet();
        final defaults = types.where((t) => canonicalRoomType(t) != null).toSet();
        // The last search's types if they still exist; otherwise discussion
        // and meeting rooms, or everything if those aren't recognised.
        final saved = _savedTypes?.intersection(types);
        _types = saved != null && saved.isNotEmpty
            ? saved
            : defaults.isNotEmpty
                ? defaults
                : types;
        _publish();
      }
      return rooms;
    } catch (e) {
      if (!_disposed) {
        _roomsError = friendlyError(e);
        _publish();
      }
      rethrow;
    } finally {
      if (!_disposed) {
        _loadingRooms = false;
        _publish();
      }
    }
  }

  void pickDay(DateTime day) => _changeSearch(() => _date = day);

  void pickStart(int startMin) => _changeSearch(() => _startMin = startMin);

  void pickDuration(int minutes) => _changeSearch(() => _duration = minutes);

  void pickType(String type, bool picked) => _changeSearch(() {
        _types = {..._types};
        picked ? _types.add(type) : _types.remove(type);
      });

  void toggleTypesExpanded() {
    _typesExpanded = !_typesExpanded;
    _publish();
  }

  void filterResults(String text) {
    _filter = text;
    _publish();
  }

  /// Any change to the search makes old results misleading, so clear them.
  void _changeSearch(VoidCallback change) {
    change();
    final starts = startOptions(_date, DateTime.now());
    if (starts.isNotEmpty && !starts.contains(_startMin)) {
      _startMin = starts.firstWhere((m) => m >= _startMin, orElse: () => starts.last);
    }
    final valid = validDurations(_startMin);
    if (!valid.contains(_duration)) _duration = valid.isEmpty ? 30 : valid.last;
    _cancelSearch();
    _searching = false;
    _stopped = false;
    _rooms = null;
    _failed = [];
    _error = null;
    _publish();
  }

  /// Checks rooms one per request, several at once, and lists each free
  /// room as soon as its answer arrives. With [only], re-checks just those
  /// rooms (the ones that failed) and keeps the results found so far.
  /// [onShowResults] is called when the results are worth scrolling to.
  Future<void> search({List<Room>? only, VoidCallback? onShowResults}) async {
    _cancelSearch();
    if (only == null) _savePrefs();
    _searching = true;
    _stopped = false;
    _error = null;
    _firstFailure = null;
    if (only == null) {
      _rooms = [];
      _failed = [];
      _filter = '';
      _checked = 0;
      _total = 0;
    } else {
      _failed = [];
      _checked = 0;
      _total = only.length;
    }
    _publish();

    try {
      final service = ref.read(bookingServiceProvider);
      final all = await loadRooms();
      final rooms = only ?? all.where((r) => _types.contains(r.rsrcTypName)).toList();
      if (_disposed) return;
      _total = rooms.length;
      _publish();
      if (only == null) onShowResults?.call();

      // Fixed now, so late answers are matched against the slot that was
      // searched even if the form changes meanwhile.
      final searched = state;
      final start = searched.startMin;
      final end = searched.endMin;
      final done = Completer<void>();
      _searchDone = done;

      _searchSub = service.checkEachRoom(rooms, searched.apiDate, hhmm(bookingOpenMin), hhmm(bookingCloseMin)).listen(
        (check) {
          if (_disposed) return;
          _checked++;
          if (check.error != null) {
            _failed.add(check.room);
            _firstFailure ??= check.error;
          } else if (check.result != null) {
            final picks = slotsInRange(check.result!.slots, start, end);
            if (picks.isNotEmpty) _rooms?.add(RoomWithSlots(check.room, picks));
          }
          _scheduleRedraw();
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future;

      // Every room failed: show it as an error rather than "no rooms free".
      if (!_disposed && _total > 0 && _failed.length == _total && (_rooms?.isEmpty ?? true)) {
        throw _firstFailure ?? Exception("Couldn't check any rooms.");
      }
    } catch (e) {
      if (!_disposed) {
        _error = friendlyError(e);
        _errorIsSession = isSessionError(e);
        _failed = [];
        _publish();
        onShowResults?.call();
      }
    } finally {
      if (!_disposed) {
        _searching = false;
        _publish();
      }
    }
  }

  /// [room] was just booked: it's no longer free, and the weekly hours and
  /// Home's next booking are out of date.
  void booked(RoomWithSlots room) {
    ref.invalidate(quotaDataProvider);
    ref.invalidate(nextBookingProvider);
    _rooms?.remove(room);
    _publish();
  }
}
