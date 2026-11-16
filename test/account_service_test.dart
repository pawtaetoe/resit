import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'rbs_username': '2100000', 'rbs_password': 'pw'});
    SharedPreferences.setMockInitialValues({'module_colours': '{}', 'graduation_year': 2027, 'book_start': '09:00'});
    // Nothing is signed in, so signing out sends no requests.
    final client = SessionClient(MockClient((r) async => http.Response('nf', 404, request: r)));
    container = ProviderContainer(overrides: [sessionClientProvider.overrideWithValue(client)]);
  });

  tearDown(() => container.dispose());

  test('the saved login says whether a password is saved, never what it is', () async {
    final login = await container.read(accountServiceProvider).savedLogin();
    expect(login.username, '2100000');
    expect(login.hasPassword, isTrue);
    expect(login.remembersPassword, isTrue);
  });

  test('signing out keeps the saved login and settings', () async {
    await container.read(accountServiceProvider).signOut(forgetDetails: false);
    expect((await container.read(accountServiceProvider).savedLogin()).username, '2100000');
    expect((await SharedPreferences.getInstance()).getInt('graduation_year'), 2027);
  });

  test('signing out and forgetting removes the login and settings about the student', () async {
    await container.read(accountServiceProvider).signOut(forgetDetails: true);
    final login = await container.read(accountServiceProvider).savedLogin();
    expect(login.username, isNull);
    expect(login.hasPassword, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNot(anyOf(contains('module_colours'), contains('graduation_year'), contains('book_start'))));
  });
}
