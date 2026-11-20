import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether a downloaded file can be handed to the device's own viewer. The
/// app's link opener does this for files on Windows, macOS and Linux only;
/// on Android and iOS it would take a file-opener plugin, so files open on
/// xSiTe in the browser there.
final opensFilesHereProvider =
    Provider<bool>((ref) => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

/// Opens a content topic: a document is downloaded and opened in the
/// device's viewer where it can be; anything else (and a document whose
/// download fails) opens in the browser.
Future<void> openTopic(BuildContext context, WidgetRef ref, ContentTopic topic) {
  if (!ref.read(opensFilesHereProvider) || !isDocument(topic)) return openInBrowser(context, topic.openUrl);
  return _openDownloaded(context, () => ref.read(topicFilesProvider).topic(topic), topic.openUrl);
}

/// Opens the course overview's attached file, or the course content on
/// xSiTe where files can't be opened here.
Future<void> openOverviewAttachment(BuildContext context, WidgetRef ref, LmsCourse course) {
  final page = contentHome(course);
  if (!ref.read(opensFilesHereProvider)) return openInBrowser(context, page);
  return _openDownloaded(context, () => ref.read(topicFilesProvider).overviewAttachment(course.orgUnitId), page);
}

/// The course's content page on xSiTe.
Uri contentHome(LmsCourse course) => Uri.parse('$xsiteBase/d2l/le/content/${course.orgUnitId}/Home');

Future<void> _openDownloaded(BuildContext context, Future<SavedFile> Function() download, Uri fallback) async {
  SavedFile? file;
  try {
    file = await download();
  } catch (_) {
    // Not readable through the API (or not a file after all): the browser
    // shows it as xSiTe does.
  }
  if (!context.mounted) return;
  if (file == null) return openInBrowser(context, fallback);
  final opened = await launchUrl(Uri.file(file.path)).catchError((_) => false);
  if (!context.mounted) return;
  if (opened) {
    showSuccess(context, 'Opened ${file.name} (${fileSizeLabel(file.size)})');
  } else {
    showError(context, "Couldn't open ${file.name} on this device.");
  }
}
