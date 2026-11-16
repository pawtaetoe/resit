import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved copies of personal data (results, timetable), encrypted at rest
/// with the platform keystore like the credentials in SecureStorage, rather
/// than in plain SharedPreferences.
///
/// Earlier versions kept some of these in SharedPreferences; the first read
/// of such a key moves it here and deletes the plaintext copy.
class PrivateStore {
  final FlutterSecureStorage _store;
  final Map<String, Future<void>> _migrated = {};

  PrivateStore([FlutterSecureStorage? store])
      : _store = store ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  /// Moves [key] out of SharedPreferences once (keeping a newer value
  /// already stored here).
  Future<void> _migrate(String key) {
    return _migrated[key] ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final legacy = prefs.getString(key);
        if (legacy == null) return;
        if (await _store.read(key: key) == null) await _store.write(key: key, value: legacy);
        await prefs.remove(key);
      } catch (_) {
        // Nothing to move, or storage unavailable: the read below decides.
      }
    }();
  }

  Future<String?> read(String key) async {
    await _migrate(key);
    return _store.read(key: key);
  }

  Future<void> write(String key, String value) async {
    await _migrate(key);
    await _store.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    await _migrate(key);
    await _store.delete(key: key);
  }
}
