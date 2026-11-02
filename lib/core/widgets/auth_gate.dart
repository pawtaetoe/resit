import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/feedback.dart';

/// Sends the user to the Account tab, closing any pushed screens.
void goToAccount(BuildContext context, WidgetRef ref) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  ref.read(homeTabProvider.notifier).state = 1;
}

/// Shows [builder]'s screen once signed in. Until then it tries to restore
/// the saved session (no MFA needed) and, if that fails, explains how to sign
/// in with a button that goes straight there.
class AuthGate extends ConsumerStatefulWidget {
  final String title;
  final WidgetBuilder builder;

  const AuthGate({super.key, required this.title, required this.builder});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!ref.read(authStateProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    }
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      // A fresh login needs MFA approval, so only the saved session is reused
      // here. If it has lapsed the user signs in from Account.
      await ref.read(authServiceProvider).resumeSession();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authStateProvider)) return widget.builder(context);

    final Widget body;
    if (_restoring || ref.watch(sessionRestoringProvider)) {
      body = const MessageView(
        icon: Icons.sync,
        title: 'Restoring your session…',
        message: 'This only takes a moment.',
        action: SizedBox(width: 160, child: LinearProgressIndicator()),
      );
    } else if (_error != null) {
      body = MessageView(
        icon: Icons.cloud_off,
        title: "Couldn't check your session",
        message: _error,
        action: FilledButton.icon(
          onPressed: _restore,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    } else {
      body = MessageView(
        icon: Icons.lock_outline,
        title: 'Sign in to continue',
        message: 'Connect your SIT account once and the app keeps you signed in.',
        action: FilledButton.icon(
          onPressed: () => goToAccount(context, ref),
          icon: const Icon(Icons.login),
          label: const Text('Go to sign in'),
        ),
      );
    }

    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }
}
