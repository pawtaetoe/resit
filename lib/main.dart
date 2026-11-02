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

  // Check the saved session on launch and sign back in automatically if it
  // has expired, so the user never has to do it by hand.
  container.read(sessionControllerProvider.notifier).ensureSignedIn();

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

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  static const _screens = [ServicesScreen(), SettingsScreen()];

  // Coming back to the app re-checks the session (and signs back in if it
  // expired while the app was in the background).
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(sessionControllerProvider.notifier).ensureSignedIn(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The session dropped while the app is open (e.g. the keep-alive found it
    // expired): sign back in right away.
    ref.listen<bool>(authStateProvider, (was, now) {
      if (was == true && !now) ref.read(sessionControllerProvider.notifier).ensureSignedIn();
    });

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
