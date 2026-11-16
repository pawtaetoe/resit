import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/app_lock.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/app/main_layout.dart';

export 'package:resit/app/main_layout.dart' show MainLayout;

class ReSitApp extends ConsumerWidget {
  const ReSitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return MaterialApp(
      title: 'reSIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // On very wide windows (desktop), keep the app in a readable centred
      // column instead of stretching every list across the screen.
      builder: (context, child) => AppLockGate(
        lock: lock,
        onUnlock: () => ref.read(appLockProvider.notifier).unlock(),
        child: child!,
      ),
      home: const MainLayout(),
    );
  }
}
