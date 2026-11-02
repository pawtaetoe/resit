import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/services/presentation/services_screen.dart';
import 'package:resit/features/settings/presentation/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SessionClient.debugCookies = kDebugMode;
  final container = ProviderContainer();

  // Restore the saved ADFS/RBS session in the background so the user does not
  // have to redo MFA on every launch. The flag lets screens say so meanwhile.
  container.read(sessionRestoringProvider.notifier).state = true;
  container.read(authServiceProvider).resumeSession().catchError((Object e) {
    debugPrint('Session restore failed: $e');
    return false;
  }).whenComplete(() => container.read(sessionRestoringProvider.notifier).state = false);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReSitApp(),
    ),
  );
}

class ReSitApp extends StatelessWidget {
  const ReSitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'reSIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const MainLayout(),
    );
  }
}

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key});

  static const _screens = [ServicesScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabProvider);
    final needsSignIn = !ref.watch(authStateProvider) && !ref.watch(sessionRestoringProvider);

    return Scaffold(
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).state = i,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            // A dot on the tab tells the user sign-in is needed.
            icon: Badge(isLabelVisible: needsSignIn, child: const Icon(Icons.person_outline)),
            selectedIcon: Badge(isLabelVisible: needsSignIn, child: const Icon(Icons.person)),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
