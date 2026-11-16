import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/core/ui/app_theme.dart';

/// The device check behind the app lock (fingerprint, face, or the device
/// PIN, pattern or password). Replaceable in tests.
abstract class DeviceCheck {
  Future<bool> isSupported();
  Future<bool> confirm(String reason);
}

class LocalAuthCheck implements DeviceCheck {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      // No implementation on this platform (Linux).
      return false;
    }
  }

  @override
  Future<bool> confirm(String reason) async {
    try {
      // Not biometric-only: the device PIN or password always works too.
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('App lock: $e');
      return false;
    }
  }
}

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

/// Covers the app while it's locked or in the background.
class AppLockGate extends StatelessWidget {
  final AppLockState lock;
  final Future<bool> Function() onUnlock;
  final Widget child;

  const AppLockGate({super.key, required this.lock, required this.onUnlock, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept alive (sign-in and loading carry on) but not painted, tappable
        // or read out while hidden.
        Offstage(offstage: lock.hidden, child: TickerMode(enabled: !lock.hidden, child: child)),
        if (lock.hidden) _LockScreen(locked: lock.locked, onUnlock: onUnlock),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  final bool locked;
  final Future<bool> Function() onUnlock;

  const _LockScreen({required this.locked, required this.onUnlock});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.locked) _askSoon();
  }

  @override
  void didUpdateWidget(_LockScreen old) {
    super.didUpdateWidget(old);
    if (widget.locked && !old.locked) _askSoon();
  }

  // Asks as soon as the lock screen shows, so unlocking is one touch.
  void _askSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnlock();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.section),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: Space.page),
                Text('reSIT is locked', style: theme.textTheme.headlineSmall),
                if (widget.locked) ...[
                  const SizedBox(height: Space.dense),
                  Text(
                    'Use your fingerprint, face or device PIN to open it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Space.section),
                  FilledButton.icon(
                    onPressed: widget.onUnlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
