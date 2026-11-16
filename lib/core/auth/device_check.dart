import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

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
