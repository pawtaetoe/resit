import 'dart:async';
import 'dart:io';

import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/network/redirects.dart';

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
  return text.isEmpty ? "Couldn't finish that. Try again." : text;
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
