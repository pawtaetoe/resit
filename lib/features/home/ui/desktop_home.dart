import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/services/ui/overview_grid.dart';
import 'package:resit/features/home/ui/session_banner.dart';
import 'package:resit/features/home/ui/up_next_card.dart';

/// Home in a desktop window: a title bar with Refresh (also Ctrl+R or F5),
/// what's next on the left and the overview on the right.
class DesktopHome extends ConsumerWidget {
  final Future<void> Function() onRefresh;
  const DesktopHome({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): onRefresh,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): onRefresh,
        const SingleActivator(LogicalKeyboardKey.f5): onRefresh,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: AppScaffold.toolbarHeight,
            titleSpacing: 24,
            automaticallyImplyLeading: false,
            title: Text(ref.watch(authStateProvider) ? 'Home' : 'Welcome to reSIT'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
            ],
            shape: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
            children: const [
              SessionBanner(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: UpNextCard()),
                  SizedBox(width: 32),
                  Expanded(child: OverviewGrid()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
