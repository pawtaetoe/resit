import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/features/lms/course_extras_providers.dart';
import 'package:resit/features/lms/data/file_opener.dart';
import 'package:resit/features/lms/data/topic_files.dart';
import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/features/lms/ui/file_view_screens.dart';
import 'package:resit/features/lms/ui/open_in_browser.dart';

/// Whether course files are downloaded and opened here (PDFs and images in
/// the app, other documents in another app on the device). Everywhere but the
/// web, where files open on xSiTe.
final opensFilesHereProvider = Provider<bool>((ref) => !kIsWeb);

/// Opens a content topic: a document is downloaded and shown in the app (PDF,
/// image) or handed to another app on the device (Word, Slides, ...);
/// anything else (videos, web pages) and a document whose download fails
/// opens in the browser.
Future<void> openTopic(BuildContext context, WidgetRef ref, ContentTopic topic) {
  if (!ref.read(opensFilesHereProvider) || !isDocument(topic)) return openInBrowser(context, topic.openUrl);
  return _openDownloaded(context, ref, () => ref.read(topicFilesProvider).topic(topic), topic.openUrl);
}

/// Opens the course overview's attached file, or the course content on
/// xSiTe where files can't be opened here.
Future<void> openOverviewAttachment(BuildContext context, WidgetRef ref, LmsCourse course) {
  final page = contentHome(course);
  if (!ref.read(opensFilesHereProvider)) return openInBrowser(context, page);
  return _openDownloaded(context, ref, () => ref.read(topicFilesProvider).overviewAttachment(course.orgUnitId), page);
}

/// The course's content page on xSiTe.
Uri contentHome(LmsCourse course) => Uri.parse('$xsiteBase/d2l/le/content/${course.orgUnitId}/Home');

Future<void> _openDownloaded(
    BuildContext context, WidgetRef ref, Future<SavedFile> Function() download, Uri fallback) async {
  SavedFile? file;
  try {
    file = await download();
  } catch (_) {
    // Not readable through the API (or not a file after all): the browser
    // shows it as xSiTe does.
  }
  if (!context.mounted) return;
  if (file == null) return openInBrowser(context, fallback);
  if (viewFor(file.name) != FileView.otherApp) {
    // Not awaited: the file's row stops showing progress once it's open.
    unawaited(Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => FileViewScreen(file: file!, onXsite: fallback))));
    return;
  }
  final opened = await ref.read(fileOpenerProvider).open(file.path);
  if (!context.mounted) return;
  if (opened) {
    showSuccess(context, 'Opened ${file.name} (${fileSizeLabel(file.size)})');
  } else {
    // Nothing on the device opens this type: xSiTe shows it in the browser.
    showError(context, 'No app on this device opens ${file.name}. Opening it on xSiTe.');
    await openInBrowser(context, fallback);
  }
}
