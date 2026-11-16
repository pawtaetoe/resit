import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/timetable/data/module_colours.dart';
import 'package:resit/features/timetable/data/timetable_store.dart';
import 'package:resit/features/timetable/domain/class_session.dart';
import 'package:resit/features/timetable/timetable_providers.dart';
import 'package:resit/features/timetable/ui/course_palette.dart';
import 'package:resit/sites/adfs/auth_service.dart';

/// What the timetable has for one week.
class TimetableWeek {
  /// The week as read from in4SIT while the screen is open.
  final WeekSchedule? live;

  /// The copy saved on the device, when there's no [live] one.
  final SavedWeek? saved;

  /// Why the week couldn't be read, if it couldn't.
  final Object? error;

  /// Whether the week is being read now.
  final bool loading;

  const TimetableWeek({this.live, this.saved, this.error, this.loading = false});

  /// The week to show: the live one, else the saved copy.
  WeekSchedule? get schedule => live ?? saved?.week;
}

/// Everything the timetable screen shows, by week.
@immutable
class TimetableState {
  // Weeks are fetched one at a time (the server keeps the page state) and
  // cached by their Monday.
  final Map<DateTime, WeekSchedule> weeks;

  /// Weeks saved on the device: shown at once, and when in4SIT can't be
  /// reached.
  final Map<DateTime, SavedWeek> saved;
  final Map<DateTime, Object> errors;
  final Set<DateTime> loading;

  /// What to do on the phone while in4SIT's own sign-in waits for MFA.
  final MfaChallenge? mfaChallenge;

  /// Module → colour, kept on the device so each module keeps its colour.
  final Map<String, int> colours;

  const TimetableState({
    this.weeks = const {},
    this.saved = const {},
    this.errors = const {},
    this.loading = const {},
    this.mfaChallenge,
    this.colours = const {},
  });

  /// The week starting [monday].
  TimetableWeek weekOf(DateTime monday) {
    final live = weeks[monday];
    return TimetableWeek(
      live: live,
      saved: live == null ? saved[monday] : null,
      error: errors[monday],
      loading: loading.contains(monday),
    );
  }

  TimetableState copyWith({
    Map<DateTime, WeekSchedule>? weeks,
    Map<DateTime, SavedWeek>? saved,
    Map<DateTime, Object>? errors,
    Set<DateTime>? loading,
    MfaChallenge? mfaChallenge,
    bool clearChallenge = false,
    Map<String, int>? colours,
  }) =>
      TimetableState(
        weeks: weeks == null ? this.weeks : Map.unmodifiable(weeks),
        saved: saved == null ? this.saved : Map.unmodifiable(saved),
        errors: errors == null ? this.errors : Map.unmodifiable(errors),
        loading: loading == null ? this.loading : Set.unmodifiable(loading),
        mfaChallenge: clearChallenge ? null : (mfaChallenge ?? this.mfaChallenge),
        colours: colours == null ? this.colours : Map.unmodifiable(colours),
      );
}

/// The timetable screen's state. Each timetable screen scopes its own, so
/// two open at once don't share weeks.
final timetableViewModelProvider =
    NotifierProvider.autoDispose<TimetableViewModel, TimetableState>(TimetableViewModel.new);

/// Reads the timetable a week at a time: the saved weeks at once, then each
/// week from in4SIT as it's shown, keeping a saved copy of each. Nothing is
/// read from in4SIT while signed out; the saved weeks are shown meanwhile.
class TimetableViewModel extends AutoDisposeNotifier<TimetableState> {
  final _colourStore = ModuleColourStore();
  bool _mounted = true;

  @override
  TimetableState build() {
    ref.onDispose(() => _mounted = false);
    ref.read(timetableWeekStoreProvider).load().then(_addSaved);
    _colourStore.load().then(_setColours);
    return const TimetableState();
  }

  /// Reads the week starting [monday], unless it's been read (or failed)
  /// already or is being read now.
  Future<void> loadWeek(DateTime monday) => _load(monday);

  /// Reads the week starting [monday] afresh, forgetting the weeks read so
  /// far.
  Future<void> refresh(DateTime monday) => _load(monday, force: true);

  void _addSaved(Map<DateTime, SavedWeek> saved) {
    if (!_mounted) return;
    saved.removeWhere((monday, _) => state.saved.containsKey(monday));
    var colours = state.colours;
    for (final w in saved.values) {
      colours = _colourModules(colours, w.week.sessions);
    }
    state = state.copyWith(saved: {...state.saved, ...saved}, colours: colours);
  }

  void _setColours(Map<String, int> saved) {
    if (!_mounted) return;
    var colours = saved;
    // Weeks that arrived before the saved colours did.
    for (final w in state.weeks.values) {
      colours = _colourModules(colours, w.sessions);
    }
    state = state.copyWith(colours: colours);
  }

  /// Gives the modules in [sessions] a colour if they don't have one yet in
  /// [colours], saving any new choice. Returns the colours.
  Map<String, int> _colourModules(Map<String, int> colours, Iterable<ClassSession> sessions) {
    final updated = assignModuleColours(colours, sessions.map((s) => s.courseCode), CoursePalette.colours.length);
    if (updated.length == colours.length) return colours;
    _colourStore.save(updated);
    return updated;
  }

  /// Loads a week. [prefetch] is a quiet look-ahead: a failure isn't kept
  /// as the week's error (it's simply asked for again when shown), and it
  /// doesn't chain another look-ahead.
  Future<void> _load(DateTime monday, {bool force = false, bool prefetch = false}) async {
    if (!ref.read(authStateProvider)) return;
    if (state.loading.contains(monday)) return;
    if (!force && (state.weeks.containsKey(monday) || state.errors.containsKey(monday))) return;

    state = state.copyWith(
      loading: {...state.loading, monday},
      errors: {...state.errors}..remove(monday),
      weeks: force ? const {} : null,
    );

    final service = ref.read(timetableServiceProvider);
    Future<WeekSchedule> fetch() => service.week(
          monday,
          onMfaChallenge: (challenge) {
            if (_mounted) state = state.copyWith(mfaChallenge: challenge);
          },
        );

    try {
      if (force) service.reset();
      final week = await (prefetch ? service.week(monday) : _withSignInRetry(fetch, beforeRetry: service.reset));
      if (!_mounted) return;
      state = state.copyWith(
        weeks: {...state.weeks, monday: week},
        saved: {...state.saved, monday: SavedWeek(week, DateTime.now())},
        colours: _colourModules(state.colours, week.sessions),
      );
      unawaited(ref.read(timetableWeekStoreProvider).save(week));
      // Swiping on is the likely next step: fetch the following week behind
      // this one (in4SIT takes one request at a time, so it just queues).
      if (!prefetch) {
        final next = DateTime(monday.year, monday.month, monday.day + 7);
        if (!state.weeks.containsKey(next)) unawaited(_load(next, prefetch: true));
      }
    } catch (e) {
      if (!_mounted) return;
      if (!prefetch) state = state.copyWith(errors: {...state.errors, monday: e});
    } finally {
      if (_mounted) state = state.copyWith(loading: {...state.loading}..remove(monday), clearChallenge: true);
    }
  }

  /// Runs [task]; if in4SIT's sign-in has lapsed, signs in to SIT afresh
  /// and tries once more, as screens do with withSignInRetry. [beforeRetry]
  /// resets anything the failed attempt left behind.
  Future<T> _withSignInRetry<T>(Future<T> Function() task, {void Function()? beforeRetry}) async {
    try {
      return await task();
    } on SessionExpiredException {
      // Closed meanwhile: no one is waiting for the week.
      if (!_mounted) rethrow;
      final signedIn = await ref.read(sessionControllerProvider.notifier).ensureSignedIn(force: true);
      if (!signedIn) rethrow;
      beforeRetry?.call();
      return task();
    }
  }
}
