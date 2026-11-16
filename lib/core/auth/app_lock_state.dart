import 'package:flutter/foundation.dart';

@immutable
class AppLockState {
  /// Whether this device can lock the app at all (false on Linux, or with
  /// no screen lock set up).
  final bool supported;
  final bool enabled;

  /// The app is hidden until the user confirms it's them.
  final bool locked;

  /// The app is covered while it's in the background (the app switcher
  /// shows the cover, not your timetable or grades).
  final bool covered;

  const AppLockState({this.supported = false, this.enabled = false, this.locked = false, this.covered = false});

  bool get hidden => locked || covered;

  AppLockState copyWith({bool? supported, bool? enabled, bool? locked, bool? covered}) => AppLockState(
        supported: supported ?? this.supported,
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        covered: covered ?? this.covered,
      );
}
