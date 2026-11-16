import 'package:flutter/material.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser (xSiTe pages need its full web app).
Future<void> openInBrowser(BuildContext context, Uri url) async {
  final ok = await launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) showError(context, "Couldn't open the browser.");
}
