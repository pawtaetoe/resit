import 'package:resit/core/auth/app_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/in4sit/peoplesoft.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/sites/adfs/totp.dart';

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});

final sessionClientProvider = Provider<SessionClient>((ref) {
  return SessionClient();
});

final authServiceProvider = Provider<AuthService>((ref) {
  final client = ref.watch(sessionClientProvider);
  final service = AuthService(client, ref.watch(secureStorageProvider));
  // Keep the UI's signed-in flag in sync when the keep-alive finds the
  // session has expired (or gets restored).
  service.onSessionChanged = (active) {
    ref.read(authStateProvider.notifier).state = active;
  };
  ref.onDispose(service.dispose);
  return service;
});

/// The one queue every in4SIT (PeopleSoft) request goes through, so the
/// timetable and the exam results don't knock out each other's page.
final in4SitQueueProvider = Provider<In4SitQueue>((ref) => In4SitQueue());

// A provider to manage the login state globally
final authStateProvider = StateProvider<bool>((ref) => false);

/// The app lock (fingerprint, face or device PIN), read once at launch.
final appLockProvider = StateNotifierProvider<AppLock, AppLockState>((ref) {
  return AppLock(ref.watch(secureStorageProvider))..init();
});

/// Checks the session and signs in again automatically when it has expired.
final sessionControllerProvider = StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref.watch(authServiceProvider), ref.watch(secureStorageProvider));
});

/// True while the app is checking the session or signing back in.
final sessionRestoringProvider = Provider<bool>((ref) => ref.watch(sessionControllerProvider).busy);

/// The bottom tabs, by position.
abstract final class AppTab {
  static const home = 0;
  static const services = 1;
  static const account = 2;
}

/// Which bottom tab is showing (see [AppTab]). Lets other screens send the
/// user to a tab, e.g. Account to sign in.
final homeTabProvider = StateProvider<int>((ref) => AppTab.home);

/// The saved authenticator secret for automatic verification codes, or null
/// when not set up. Invalidate after saving or removing it.
final totpConfigProvider = FutureProvider<TotpConfig?>((ref) async {
  final saved = await ref.watch(secureStorageProvider).getTotp();
  if (saved == null || saved.isEmpty) return null;
  try {
    return TotpConfig.parse(saved);
  } catch (_) {
    return null;
  }
});
