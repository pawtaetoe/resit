import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/services/presentation/services_screen.dart';
import 'package:resit/features/settings/presentation/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SessionClient.debugCookies = kDebugMode;
  final container = ProviderContainer();

  // Restore the saved ADFS/RBS session in the background so the user does not
  // have to redo MFA on every launch.
  container.read(authServiceProvider).resumeSession().catchError((Object e) {
    debugPrint('Session restore failed: $e');
    return false;
  });

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ServicesScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
