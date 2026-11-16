import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/app_lock_state.dart';
import 'package:resit/core/auth/device_check.dart';
import 'package:resit/core/storage/secure_storage.dart';

// The lock's state, the device check behind it and the widget that covers
// the app live next to this file; importing this one brings them in.
export 'package:resit/core/auth/app_lock_gate.dart' show AppLockGate;
export 'package:resit/core/auth/app_lock_state.dart' show AppLockState;
export 'package:resit/core/auth/device_check.dart' show DeviceCheck, LocalAuthCheck;

/// Locks the app behind the device's fingerprint, face or screen lock: at
/// launch, and after it has been in the background for [grace] or longer.
/// The saved sign-in stays, so SIT's frequent timeouts still don't mean
/// signing in again; the lock stops someone else holding the phone from
/// opening the app (and its saved password and verification codes).
class AppLock extends StateNotifier<AppLockState> {
  static const grace = Duration(seconds: 30);

  final SecureStorage _storage;
  final DeviceCheck _check;
  final DateTime Function() _now;
  AppLifecycleListener? _lifecycle;
  DateTime? _leftAt;
  bool _confirming = false;

  AppLock(this._storage, {DeviceCheck? check, DateTime Function()? now, bool watchLifecycle = true})
      : _check = check ?? LocalAuthCheck(),
        _now = now ?? DateTime.now,
        super(const AppLockState()) {
    if (watchLifecycle) _lifecycle = AppLifecycleListener(onStateChange: appLifecycleChanged);
  }

  /// Reads the setting; locks straight away if it's on.
  Future<void> init() async {
    final supported = await _check.isSupported();
    final enabled = supported && await _storage.appLockEnabled();
    if (!mounted) return;
    state = state.copyWith(supported: supported, enabled: enabled, locked: enabled || state.locked);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void appLifecycleChanged(AppLifecycleState lifecycle) {
    // The fingerprint prompt itself sends the app to the background.
    if (_confirming || !state.enabled) return;
    final away = switch (lifecycle) {
      AppLifecycleState.hidden || AppLifecycleState.paused => true,
      // On phones "inactive" is the app switcher: cover it there too. On
      // desktop it only means another window has focus.
      AppLifecycleState.inactive => !kIsWeb && (Platform.isIOS || Platform.isAndroid),
      _ => false,
    };
    if (away) {
      _leftAt ??= _now();
      if (!state.covered) state = state.copyWith(covered: true);
    } else if (lifecycle == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      final lock = left != null && _now().difference(left) >= grace;
      state = state.copyWith(covered: false, locked: state.locked || lock);
    }
  }

  Future<bool> _confirm(String reason) async {
    if (_confirming) return false;
    _confirming = true;
    try {
      return await _check.confirm(reason);
    } finally {
      _confirming = false;
      _leftAt = null;
    }
  }

  Future<bool> unlock() async {
    final ok = await _confirm('Unlock reSIT');
    if (ok && mounted) state = state.copyWith(locked: false, covered: false);
    return ok;
  }

  /// Turning the lock on or off both need the device check, so someone
  /// holding an unlocked phone can't simply switch it off.
  Future<bool> setEnabled(bool on) async {
    if (on == state.enabled) return true;
    if (!state.supported) return false;
    final ok = await _confirm(on ? 'Turn on the app lock' : 'Turn off the app lock');
    if (!ok) return false;
    await _storage.setAppLockEnabled(on);
    if (mounted) state = state.copyWith(enabled: on, locked: false, covered: false);
    return true;
  }
}
