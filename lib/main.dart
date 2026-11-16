import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/app/app.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/storage/secure_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SessionClient.debugCookies = kDebugMode;
  // Before anything reads the saved login: a reinstalled app on Apple
  // devices must not pick up the last install's password.
  await SecureStorage.wipeIfReinstalled(
      apple: !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS));
  final container = ProviderContainer();

  // Check the saved session on launch and sign back in automatically if it
  // has expired, so the user never has to do it by hand.
  container.read(sessionControllerProvider.notifier).ensureSignedIn();
  // Locks at once if the app lock is on.
  container.read(appLockProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReSitApp(),
    ),
  );
}
