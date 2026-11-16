import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/app_lock.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/calendar/presentation/academic_calendar_screen.dart';
import 'package:resit/features/exams/presentation/academic_progress_screen.dart';
import 'package:resit/features/exams/presentation/exam_results_screen.dart';
import 'package:resit/features/lms/presentation/courses_screen.dart';
import 'package:resit/features/room_booking/presentation/dashboard_screen.dart';
import 'package:resit/features/room_booking/presentation/manage_booking_screen.dart';
import 'package:resit/features/timetable/presentation/timetable_screen.dart';
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
  // Locks at once if the app lock is on.
  container.read(appLockProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ReSitApp(),
    ),
  );
}

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

  /// The desktop sidebar: everything in Services listed directly, grouped by
  /// the SIT system it comes from.
  static final _desktop = [
    DesktopDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home', builder: (_) => const HomeScreen()),
    DesktopDestination(
        group: 'in4SIT',
        icon: Icons.view_week_outlined,
        selectedIcon: Icons.view_week,
        label: 'Timetable',
        builder: (_) => const TimetableScreen()),
    DesktopDestination(
        group: 'in4SIT',
        icon: Icons.grading_outlined,
        selectedIcon: Icons.grading,
        label: 'Exam results',
        builder: (_) => const ExamResultsScreen()),
    DesktopDestination(
        group: 'in4SIT',
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights,
        label: 'Academic progress',
        builder: (_) => const AcademicProgressScreen()),
    DesktopDestination(
        group: 'xSiTe',
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book,
        label: 'Courses',
        builder: (_) => const CoursesScreen()),
    DesktopDestination(
        group: 'Room booking',
        icon: Icons.meeting_room_outlined,
        selectedIcon: Icons.meeting_room,
        label: 'Book a room',
        builder: (_) => const DashboardScreen()),
    DesktopDestination(
        group: 'Room booking',
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note,
        label: 'My bookings',
        builder: (_) => const ManageBookingScreen()),
    DesktopDestination(
        group: 'General',
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: 'Academic calendar',
        builder: (_) => const AcademicCalendarScreen()),
    DesktopDestination(
        group: 'General',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: 'Account',
        builder: (_) => const SettingsScreen()),
  ];
  static final _deskAccount = _desktop.length - 1;

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
        destinations: _desktop,
        selected: _desk,
        onSelect: (i) {
          setState(() => _desk = i);
          ref.read(homeTabProvider.notifier).state = i == 0
              ? AppTab.home
              : i == _deskAccount
                  ? AppTab.account
                  : AppTab.services;
        },
        header: const _SidebarHeader(),
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

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 're', style: TextStyle(color: theme.colorScheme.secondary)),
              TextSpan(text: 'SIT', style: TextStyle(color: theme.colorScheme.primary)),
            ]),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            semanticsLabel: 'reSIT',
          ),
          Text('SIT, in one place',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
