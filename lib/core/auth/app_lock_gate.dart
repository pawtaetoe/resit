import 'package:flutter/material.dart';
import 'package:resit/core/auth/app_lock_state.dart';
import 'package:resit/core/ui/app_theme.dart';

/// Covers the app while it's locked or in the background.
class AppLockGate extends StatelessWidget {
  final AppLockState lock;
  final Future<bool> Function() onUnlock;
  final Widget child;

  const AppLockGate({super.key, required this.lock, required this.onUnlock, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept alive (sign-in and loading carry on) but not painted, tappable
        // or read out while hidden.
        Offstage(offstage: lock.hidden, child: TickerMode(enabled: !lock.hidden, child: child)),
        if (lock.hidden) _LockScreen(locked: lock.locked, onUnlock: onUnlock),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  final bool locked;
  final Future<bool> Function() onUnlock;

  const _LockScreen({required this.locked, required this.onUnlock});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.locked) _askSoon();
  }

  @override
  void didUpdateWidget(_LockScreen old) {
    super.didUpdateWidget(old);
    if (widget.locked && !old.locked) _askSoon();
  }

  // Asks as soon as the lock screen shows, so unlocking is one touch.
  void _askSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnlock();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.section),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: Space.page),
                Text('reSIT is locked', style: theme.textTheme.headlineSmall),
                if (widget.locked) ...[
                  const SizedBox(height: Space.dense),
                  Text(
                    'Use your fingerprint, face or device PIN to open it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Space.section),
                  FilledButton.icon(
                    onPressed: widget.onUnlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
