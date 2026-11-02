import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/ui/app_theme.dart';

/// Turns an exception into a sentence a student can act on.
String friendlyError(Object error) {
  if (error is SessionExpiredException) {
    return "Your session expired and the app couldn't sign you back in automatically.";
  }
  if (error is MfaException) return error.message;
  if (error is SocketException || error is HandshakeException) {
    return "Can't reach the school servers. Check your internet connection and try again.";
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond. Try again in a moment.';
  }
  final text = error.toString().replaceFirst(RegExp(r'^(Exception|ClientException):\s*'), '');
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return "Can't reach the school servers. Check your internet connection and try again.";
  }
  return text.isEmpty ? 'Something went wrong. Try again.' : text;
}

bool isSessionError(Object error) => error is SessionExpiredException;

/// Technical detail behind an error, worth showing small for troubleshooting
/// (e.g. which sign-in page a failed single sign-on ended on).
String? errorDetail(Object error) => error is SessionExpiredException ? error.detail : null;

void showSuccess(BuildContext context, String message, {SnackBarAction? action}) =>
    _show(context, message, Icons.check_circle_outline, action: action);

void showError(BuildContext context, String message) =>
    _show(context, message, Icons.error_outline, error: true);

void _show(BuildContext context, String message, IconData icon,
    {bool error = false, SnackBarAction? action}) {
  final scheme = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    backgroundColor: error ? scheme.error : null,
    action: action,
    content: Row(
      children: [
        Icon(icon, color: error ? scheme.onError : scheme.onInverseSurface),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    ),
  ));
}

/// Centered icon + title + explanation + optional action. Used for empty,
/// error and signed-out states so they all look and behave the same.
class MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Tone tone;

  /// Small selectable technical text under the message, for troubleshooting.
  final String? detail;

  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = Tone.neutral,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = tone.colors(theme.colorScheme);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 36, backgroundColor: bg, child: Icon(icon, size: 36, color: fg)),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (detail != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tinted label, e.g. a booking status.
class StatusPill extends StatelessWidget {
  final String label;
  final Tone tone;
  final IconData? icon;

  const StatusPill({super.key, required this.label, required this.tone, this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Button that shows a spinner and a "doing it" label while busy, so the
/// user sees the tap registered and can't fire it twice.
class BusyButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;
  final String label;
  final String busyLabel;
  final IconData? icon;
  final bool danger;

  const BusyButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.busyLabel,
    this.busy = false,
    this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = danger
        ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
        : null;
    return FilledButton(
      style: style,
      onPressed: busy ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSurfaceVariant),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          const SizedBox(width: 10),
          Text(busy ? busyLabel : label),
        ],
      ),
    );
  }
}
