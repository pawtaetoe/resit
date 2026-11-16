import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credentials and session cookies, encrypted at rest with the platform
/// keystore (Android Keystore-backed AES, iOS/macOS Keychain, Windows DPAPI).
class SecureStorage {
  static const _keyUsername = 'rbs_username';
  static const _keyPassword = 'rbs_password';
  static const _keySession = 'rbs_session_cookies';
  static const _keyTotp = 'mfa_totp_uri';
  static const _keySignedOut = 'signed_out';
  static const _keyForgetPassword = 'forget_password';
  static const _keyAppLock = 'app_lock';

  /// The password while the app is open, when the user chose not to keep it
  /// on the device: never written anywhere.
  String? _sessionPassword;

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

  /// Saves the login. The password is kept on the device only if
  /// [remembersPassword]; otherwise only until the app is closed.
  Future<void> saveCredentials(String username, String password) async {
    await _migrateLegacy();
    await _store.write(key: _keyUsername, value: username);
    _sessionPassword = password;
    if (await remembersPassword()) {
      await _store.write(key: _keyPassword, value: password);
    } else {
      await _store.delete(key: _keyPassword);
    }
  }

  Future<Map<String, String?>> getCredentials() async {
    await _migrateLegacy();
    return {
      'username': await _store.read(key: _keyUsername),
      'password': await _store.read(key: _keyPassword) ?? _sessionPassword,
    };
  }

  /// Whether the password is kept on the device (encrypted) so the app can
  /// sign back in after it's been closed. On by default.
  Future<bool> remembersPassword() async => await _store.read(key: _keyForgetPassword) != '1';

  /// Turning it off deletes the saved password at once (it's kept in memory
  /// until the app closes); turning it on saves the password in use.
  Future<void> setRemembersPassword(bool remember) async {
    await _migrateLegacy();
    if (remember) {
      await _store.delete(key: _keyForgetPassword);
      final password = _sessionPassword;
      if (password != null) await _store.write(key: _keyPassword, value: password);
    } else {
      _sessionPassword ??= await _store.read(key: _keyPassword);
      await _store.write(key: _keyForgetPassword, value: '1');
      await _store.delete(key: _keyPassword);
    }
  }

  Future<bool> appLockEnabled() async => await _store.read(key: _keyAppLock) == '1';

  Future<void> setAppLockEnabled(bool on) =>
      on ? _store.write(key: _keyAppLock, value: '1') : _store.delete(key: _keyAppLock);

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
    _sessionPassword = null;
  }

  /// The authenticator setup link (otpauth://...) used to fill MFA
  /// verification codes automatically.
  Future<void> saveTotp(String otpauthUri) => _store.write(key: _keyTotp, value: otpauthUri);

  Future<String?> getTotp() => _store.read(key: _keyTotp);

  Future<void> clearTotp() => _store.delete(key: _keyTotp);

  /// Set when the user signs out on purpose, so the app doesn't sign itself
  /// back in with the saved credentials until they sign in again.
  Future<void> setSignedOut(bool value) =>
      value ? _store.write(key: _keySignedOut, value: '1') : _store.delete(key: _keySignedOut);

  Future<bool> isSignedOut() async => await _store.read(key: _keySignedOut) == '1';
}
