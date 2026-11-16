import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resit/core/auth/app_lock.dart';
import 'package:resit/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCheck implements DeviceCheck {
  bool supported = true;
  bool answer = true;
  int asked = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> confirm(String reason) async {
    asked++;
    return answer;
  }
}

void main() {
  late SecureStorage storage;
  late _FakeCheck check;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    storage = SecureStorage();
    check = _FakeCheck();
    now = DateTime(2026, 11, 16, 9);
  });

  AppLock make() => AppLock(storage, check: check, now: () => now, watchLifecycle: false);

  group('AppLock', () {
    test('is off by default and never locks', () async {
      final lock = make();
      await lock.init();
      expect(lock.state.enabled, isFalse);
      expect(lock.state.hidden, isFalse);
      lock.appLifecycleChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      lock.appLifecycleChanged(AppLifecycleState.resumed);
      expect(lock.state.hidden, isFalse);
    });

    test('turning it on needs the device check, and it locks at the next launch', () async {
      final lock = make();
      await lock.init();
      check.answer = false;
      expect(await lock.setEnabled(true), isFalse);
      expect(lock.state.enabled, isFalse);

      check.answer = true;
      expect(await lock.setEnabled(true), isTrue);
      expect(lock.state.enabled, isTrue);
      expect(lock.state.locked, isFalse, reason: 'just confirmed');

      final next = make();
      await next.init();
      expect(next.state.locked, isTrue);
      expect(await next.unlock(), isTrue);
      expect(next.state.hidden, isFalse);
    });

    test('covers in the background; locks only after the grace period', () async {
      await storage.setAppLockEnabled(true);
      final lock = make();
      await lock.init();
      await lock.unlock();

      lock.appLifecycleChanged(AppLifecycleState.paused);
      expect(lock.state.covered, isTrue);
      now = now.add(AppLock.grace - const Duration(seconds: 1));
      lock.appLifecycleChanged(AppLifecycleState.resumed);
      expect(lock.state.hidden, isFalse);

      lock.appLifecycleChanged(AppLifecycleState.hidden);
      now = now.add(AppLock.grace);
      lock.appLifecycleChanged(AppLifecycleState.resumed);
      expect(lock.state.locked, isTrue);

      check.answer = false;
      expect(await lock.unlock(), isFalse);
      expect(lock.state.locked, isTrue);
    });

    test('turning it off needs the device check too', () async {
      await storage.setAppLockEnabled(true);
      final lock = make();
      await lock.init();
      check.answer = false;
      expect(await lock.setEnabled(false), isFalse);
      expect(await storage.appLockEnabled(), isTrue);
    });

    test('unsupported devices (Linux, no screen lock) never lock', () async {
      await storage.setAppLockEnabled(true);
      check.supported = false;
      final lock = make();
      await lock.init();
      expect(lock.state.supported, isFalse);
      expect(lock.state.locked, isFalse);
      expect(await lock.setEnabled(true), isFalse);
    });
  });

  group('Remember my password', () {
    test('on by default: the password is kept on the device', () async {
      await storage.saveCredentials('2100000', 'pw');
      expect((await SecureStorage().getCredentials())['password'], 'pw');
    });

    test('off: kept only in memory, deleted from the device', () async {
      await storage.saveCredentials('2100000', 'pw');
      await storage.setRemembersPassword(false);
      expect((await storage.getCredentials())['password'], 'pw', reason: 'still usable while the app is open');

      // A fresh start of the app: only the student ID is left.
      final restarted = SecureStorage();
      final creds = await restarted.getCredentials();
      expect(creds['username'], '2100000');
      expect(creds['password'], isNull);

      // Signing in again doesn't save it either.
      await restarted.saveCredentials('2100000', 'pw2');
      expect((await SecureStorage().getCredentials())['password'], isNull);
      expect((await restarted.getCredentials())['password'], 'pw2');
    });

    test('turning it back on saves the password in use', () async {
      await storage.setRemembersPassword(false);
      await storage.saveCredentials('2100000', 'pw');
      await storage.setRemembersPassword(true);
      expect((await SecureStorage().getCredentials())['password'], 'pw');
    });

    test('forgetting the login clears the in-memory password too', () async {
      await storage.setRemembersPassword(false);
      await storage.saveCredentials('2100000', 'pw');
      await storage.clearCredentials();
      expect((await storage.getCredentials())['password'], isNull);
    });
  });

  testWidgets('the gate hides the app while locked and asks at once', (tester) async {
    var asked = 0;
    Future<bool> unlock() async {
      asked++;
      return false;
    }

    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppLockGate(
        lock: const AppLockState(supported: true, enabled: true, locked: true),
        onUnlock: unlock,
        child: child!,
      ),
      home: const Text('Secret grades'),
    ));
    await tester.pump();
    expect(find.text('Secret grades'), findsNothing);
    expect(find.text('reSIT is locked'), findsOneWidget);
    expect(asked, 1);
    await tester.tap(find.text('Unlock'));
    expect(asked, 2);
  });
}
