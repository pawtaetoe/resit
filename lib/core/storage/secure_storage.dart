import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credentials and session cookies, encrypted at rest with the platform
/// keystore (Android Keystore-backed AES, iOS/macOS Keychain, Windows DPAPI).
class SecureStorage {
  static const _keyUsername = 'rbs_username';
  static const _keyPassword = 'rbs_password';
  static const _keySession = 'rbs_session_cookies';
  static const _keyTotp = 'mfa_totp_uri';

  final FlutterSecureStorage _store;
  Future<void>? _migration;

  SecureStorage([FlutterSecureStorage? store])
      : _store = store ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  /// Earlier versions kept these in plain SharedPreferences. Move anything
  /// found there into secure storage once, then delete the plaintext copy.
  Future<void> _migrateLegacy() {
    return _migration ??= () async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [_keyUsername, _keyPassword, _keySession]) {
        final legacy = prefs.getString(key);
        if (legacy == null) continue;
        if (await _store.read(key: key) == null) {
          await _store.write(key: key, value: legacy);
        }
        await prefs.remove(key);
      }
    }();
  }

  Future<void> saveCredentials(String username, String password) async {
    await _migrateLegacy();
    await _store.write(key: _keyUsername, value: username);
    await _store.write(key: _keyPassword, value: password);
  }

  Future<Map<String, String?>> getCredentials() async {
    await _migrateLegacy();
    return {
      'username': await _store.read(key: _keyUsername),
      'password': await _store.read(key: _keyPassword),
    };
  }

  Future<void> saveSession(String cookiesJson) async {
    await _migrateLegacy();
    await _store.write(key: _keySession, value: cookiesJson);
  }

  Future<String?> getSession() async {
    await _migrateLegacy();
    return _store.read(key: _keySession);
  }

  Future<void> clearSession() async {
    await _migrateLegacy();
    await _store.delete(key: _keySession);
  }

  Future<void> clearCredentials() async {
    await _migrateLegacy();
    await _store.delete(key: _keyUsername);
    await _store.delete(key: _keyPassword);
  }

  /// The authenticator setup link (otpauth://...) used to fill MFA
  /// verification codes automatically.
  Future<void> saveTotp(String otpauthUri) => _store.write(key: _keyTotp, value: otpauthUri);

  Future<String?> getTotp() => _store.read(key: _keyTotp);

  Future<void> clearTotp() => _store.delete(key: _keyTotp);
}
