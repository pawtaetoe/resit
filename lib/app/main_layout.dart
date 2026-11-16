import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/home/ui/home_screen.dart';
import 'package:resit/features/services/ui/services_screen.dart';
import 'package:resit/features/settings/ui/settings_screen.dart';
import 'package:resit/app/desktop_sidebar.dart';

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  // In the order of [AppTab].
  final Set<int> _visited = {};

  static const _screens = [HomeScreen(), ServicesScreen(), SettingsScreen()];

  /// Windows at least this wide get the desktop layout.
  static const desktopWidth = 900.0;

  static final _deskAccount = desktopDestinations.length - 1;

  /// The open part of the desktop sidebar.
  int _desk = 0;

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
    // "Sign in" buttons elsewhere switch to Account (or back Home) on desktop too.
    ref.listen<int>(homeTabProvider, (_, tab) {
      final want = tab == AppTab.account ? _deskAccount : (tab == AppTab.home ? 0 : null);
      if (want != null && want != _desk) setState(() => _desk = want);
    });
    final needsSignIn = !ref.watch(authStateProvider) && !ref.watch(sessionRestoringProvider);

    void select(int i) => ref.read(homeTabProvider.notifier).state = i;
    final tabs = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.apps_outlined, Icons.apps, 'Services'),
      (Icons.person_outline, Icons.person, 'Account'),
    ];
    // A dot on Account tells the user sign-in is needed (and screen readers
    // hear it).
    Widget icon(int i, bool selected) {
      final glyph = Icon(selected ? tabs[i].$2 : tabs[i].$1);
      if (i != AppTab.account) return glyph;
      return Semantics(
        label: needsSignIn ? 'sign-in needed' : null,
        child: Badge(isLabelVisible: needsSignIn, child: glyph),
      );
    }

    // A tab is built the first time it's opened, then kept, so Account's
    // reads (saved login, codes) don't run at launch.
    _visited.add(index);
    final body = IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < _screens.length; i++) _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
      ],
    );

    // Desktop windows get the sidebar layout; phones and tablets keep the
    // tabs at the bottom, within thumb reach.
    if (MediaQuery.sizeOf(context).width >= desktopWidth) {
      return DesktopShell(
        destinations: desktopDestinations,
        selected: _desk,
        onSelect: (i) {
          setState(() => _desk = i);
          ref.read(homeTabProvider.notifier).state = i == 0
              ? AppTab.home
              : i == _deskAccount
                  ? AppTab.account
                  : AppTab.services;
        },
        header: const SidebarHeader(),
        badge: (i) => i == _deskAccount && needsSignIn
            ? Semantics(label: 'sign-in needed', child: const Badge(smallSize: 8))
            : null,
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
