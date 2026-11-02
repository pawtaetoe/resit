import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/features/home/presentation/home_screen.dart';
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
      // On very wide windows (desktop), keep the app in a readable centred
      // column instead of stretching every list across the screen.
      builder: (context, child) => _ReadableWidth(child: child!),
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
  // In the order of [AppTab].
  static const _screens = [HomeScreen(), ServicesScreen(), SettingsScreen()];

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

    void select(int i) => ref.read(homeTabProvider.notifier).state = i;
    final tabs = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.apps_outlined, Icons.apps, 'Services'),
      (Icons.person_outline, Icons.person, 'Account'),
    ];
    // A dot on Account tells the user sign-in is needed.
    Widget icon(int i, bool selected) {
      final glyph = Icon(selected ? tabs[i].$2 : tabs[i].$1);
      return i == AppTab.account ? Badge(isLabelVisible: needsSignIn, child: glyph) : glyph;
    }

    final body = IndexedStack(index: index, children: _screens);

    // Wide windows (desktop, tablets) get a side rail; phones keep the tabs
    // at the bottom, within thumb reach.
    if (MediaQuery.sizeOf(context).width >= 720) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              destinations: [
                for (var i = 0; i < tabs.length; i++)
                  NavigationRailDestination(
                    icon: icon(i, false),
                    selectedIcon: icon(i, true),
                    label: Text(tabs[i].$3),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: [
          for (var i = 0; i < tabs.length; i++)
            NavigationDestination(icon: icon(i, false), selectedIcon: icon(i, true), label: tabs[i].$3),
        ],
      ),
    );
  }
}

/// On wide windows (above 900 px, i.e. desktop windows), keeps the app in a
/// centred 840 px column so lists, forms and buttons stay a readable width.
/// The sides match the app's background, with a hairline at the column's
/// edges.
class _ReadableWidth extends StatelessWidget {
  static const maxWidth = 840.0;
  static const capAbove = 900.0;
  final Widget child;
  const _ReadableWidth({required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width <= capAbove) return child;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.symmetric(vertical: BorderSide(color: scheme.outlineVariant)),
          ),
          child: MediaQuery(
            // Screens inside see the column's width, so they lay out for it.
            data: MediaQuery.of(context).copyWith(size: Size(maxWidth, size.height)),
            child: SizedBox(width: maxWidth, child: child),
          ),
        ),
      ),
    );
  }
}
