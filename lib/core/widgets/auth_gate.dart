import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/core/widgets/desktop.dart';

/// Runs [task]; if a school system's sign-in has lapsed, signs in to SIT
/// afresh automatically and tries once more, instead of asking the user to.
/// [beforeRetry] resets anything the failed attempt left behind.
Future<T> withSignInRetry<T>(WidgetRef ref, Future<T> Function() task, {void Function()? beforeRetry}) async {
  try {
    return await task();
  } on SessionExpiredException {
    final signedIn = await ref.read(sessionControllerProvider.notifier).ensureSignedIn(force: true);
    if (!signedIn) rethrow;
    beforeRetry?.call();
    return task();
  }
}

/// Sends the user to the Account tab, closing any pushed screens.
void goToAccount(BuildContext context, WidgetRef ref) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  ref.read(homeTabProvider.notifier).state = AppTab.account;
}

/// Shows [builder]'s screen once signed in. Until then it asks the session
/// controller to sign back in automatically (saved credentials, automatic
/// MFA codes) and shows its progress. Only when there's nothing saved, or
/// the user signed out on purpose, does it point to Account.
class AuthGate extends ConsumerStatefulWidget {
  final String title;
  final WidgetBuilder builder;

  /// What to show instead of the "signing in" and "couldn't sign in" states,
  /// for screens that have a saved copy to show meanwhile. MFA prompts and
  /// the "sign in to continue" state still come from the gate.
  final Widget Function(BuildContext context, SessionState session)? offlineBuilder;

  const AuthGate({super.key, required this.title, required this.builder, this.offlineBuilder});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (!ref.read(authStateProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _signIn());
    }
  }

  void _signIn() => ref.read(sessionControllerProvider.notifier).ensureSignedIn();

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authStateProvider)) return widget.builder(context);

    final session = ref.watch(sessionControllerProvider);
    final offline = widget.offlineBuilder;
    final waiting = session.phase == SessionPhase.idle || (session.busy && session.challenge == null);
    if (offline != null && (waiting || session.phase == SessionPhase.failed)) return offline(context, session);

    final Widget body;
    Widget? action;

    if (session.challenge != null && session.phase == SessionPhase.signingIn) {
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: MfaCard(challenge: session.challenge!),
        ),
      );
      action = FilledButton.tonalIcon(
        onPressed: () => ref.read(sessionControllerProvider.notifier).cancelSignIn(),
        icon: const Icon(Icons.close),
        label: const Text('Cancel sign-in'),
      );
    } else if (session.busy || session.phase == SessionPhase.idle) {
      body = MessageView(
        icon: Icons.sync,
        title: session.phase == SessionPhase.signingIn ? 'Signing you back in…' : 'Checking your session…',
        message: 'This only takes a moment.',
        action: const SizedBox(width: 160, child: LinearProgressIndicator()),
      );
    } else if (session.phase == SessionPhase.failed) {
      body = MessageView(
        icon: Icons.cloud_off,
        tone: Tone.danger,
        title: "Couldn't sign you in",
        message: session.error ?? 'Check your connection, then try again.',
      );
      action = FilledButton.icon(
        onPressed: _signIn,
        icon: const Icon(Icons.refresh),
        label: const Text('Try again'),
      );
    } else {
      body = const MessageView(
        icon: Icons.lock_outline,
        title: 'Sign in to continue',
        message: 'Sign in with your SIT account once; after that the app signs you back in automatically.',
      );
      action = FilledButton.icon(
        onPressed: () => goToAccount(context, ref),
        icon: const Icon(Icons.login),
        label: const Text('Go to sign in'),
      );
    }

    // The action goes in the bottom bar, next to back, within thumb reach.
    return AppScaffold(
      appBar: thumbAppBar(widget.title),
      body: body,
      bottomNavigationBar: ThumbBar(
        child: action,
      ),
    );
  }
}
