import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/session_client.dart';
import 'package:resit/core/ui/app_theme.dart';

const _offline = "Can't reach SIT's servers. Check your internet connection and try again.";
const _serverDown = "SIT's system isn't responding properly right now. Try again in a minute.";

/// Messages from the services that are technical, mapped to what a student
/// can do about them. Checked in order; the first match wins.
final List<(RegExp, String)> _plainMessages = [
  (RegExp(r'SocketException|Failed host lookup|Connection (refused|reset|closed)', caseSensitive: false), _offline),
  (RegExp(r'password page|Check your (Student ID|credentials)|No wresult|ADFS sign-in failed', caseSensitive: false),
      "Your student ID or password wasn't accepted. Check them in Account."),
  (RegExp(r'Timed out waiting for Microsoft Authenticator', caseSensitive: false),
      'The sign-in wasn\'t approved in time. Open Microsoft Authenticator and try again.'),
  (RegExp(r'MFA page has no form|No redirect to ADFS|Failed to fetch protected page|Too many redirects',
          caseSensitive: false),
      "SIT's sign-in page didn't respond as expected. Try again in a moment."),
  (RegExp(r'CSRF token|Initiate failed|Confirm failed|Booking failed', caseSensitive: false),
      "The booking didn't go through. The room may have just been taken; search again."),
  (RegExp(r'Cancellation failed', caseSensitive: false),
      "The booking couldn't be cancelled. Try again, or cancel it on the booking website."),
  (RegExp(r'Failed to (get rooms|get bookings|check availability)', caseSensitive: false),
      "Couldn't get the room bookings from SIT. Try again in a minute."),
  (RegExp(r'weekly schedule|Failed to load timetable', caseSensitive: false),
      "in4SIT didn't send your timetable. Try again in a moment."),
  (RegExp(r'list of terms', caseSensitive: false), "in4SIT didn't send your results. Try again in a moment."),
  (RegExp(r'returned [45]\d\d|status [45]\d\d|: [45]\d\d\b', caseSensitive: false), _serverDown),
];

/// Turns an exception into a sentence a student can act on. The original
/// text is still available from [errorDetail] for troubleshooting.
String friendlyError(Object error) {
  if (error is SessionExpiredException) {
    return "You're signed out of SIT's systems and the app couldn't sign you back in. "
        'Check your details in Account, then try again.';
  }
  if (error is SignInCancelledException) return 'Sign-in cancelled.';
  if (error is UntrustedHostException || error is UnsafeRedirectException) {
    return "SIT's sign-in sent the app somewhere it doesn't trust, so it stopped. Try again later.";
  }
  if (error is SocketException || error is HandshakeException || error is HttpException) return _offline;
  if (error is TimeoutException) return 'SIT took too long to respond. Try again in a moment.';
  final text = _rawText(error);
  for (final (pattern, message) in _plainMessages) {
    if (pattern.hasMatch(text)) return message;
  }
  // MFA messages written for students (e.g. "Set up automatic codes…") and
  // other plain sentences pass through.
  return text.isEmpty ? 'Something went wrong. Try again.' : text;
}

String _rawText(Object error) => error is MfaException
    ? error.message
    : error.toString().replaceFirst(RegExp(r'^(Exception|ClientException|HttpException):\s*'), '');

bool isSessionError(Object error) => error is SessionExpiredException;

/// The technical text behind an error, for the collapsed "Technical
/// details" under an error message. Null when there's nothing more to say.
String? errorDetail(Object error) {
  if (error is SessionExpiredException) return error.detail;
  final raw = _rawText(error);
  return raw.isEmpty || raw == friendlyError(error) ? null : raw;
}

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

  /// Technical text for troubleshooting, shown collapsed under the message.
  final String? detail;

  /// For use inside a list (less padding, not centred in the screen).
  final bool compact;

  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = Tone.neutral,
    this.detail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = tone.colors(theme.colorScheme);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 32),
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
                const SizedBox(height: 8),
                // Kept out of the way: it's for troubleshooting, not reading.
                ExpansionTile(
                  title: Text('Technical details',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 48),
                  children: [
                    SelectableText(
                      detail!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
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
          Flexible(
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600)),
          ),
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
