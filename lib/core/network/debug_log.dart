import 'package:flutter/foundation.dart';

/// Console logging that is compiled out of release builds, so URLs and page
/// contents from the sign-in flow never reach the device log in production.
void debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}
