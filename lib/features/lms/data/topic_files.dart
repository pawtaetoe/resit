import 'dart:io';

import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/xsite/course_extras_service.dart';

/// A file from xSiTe saved for opening: where it is, its name and size.
typedef SavedFile = ({String path, String name, int size});

/// Course files downloaded from xSiTe into a private temporary folder, so
/// the device's own viewer can open them. The folder is made for this run of
/// the app (readable by this user only), folders from earlier runs are
/// removed, and [clear] (on sign-out) deletes everything.
class TopicFiles {
  static const _prefix = 'resit-xsite-';

  final XsiteCourseExtras _xsite;
  final Directory Function() _tempRoot;
  Future<Directory>? _dir;
  final Map<String, SavedFile> _saved = {};

  TopicFiles(this._xsite, {Directory Function()? tempRoot}) : _tempRoot = tempRoot ?? (() => Directory.systemTemp);

  /// A content topic's file, downloaded once per run of the app.
  Future<SavedFile> topic(ContentTopic topic) =>
      _keep('${topic.orgUnitId}-${topic.id}', () => _xsite.topicFile(topic));

  /// The course overview's attachment.
  Future<SavedFile> overviewAttachment(String orgUnitId) =>
      _keep('$orgUnitId-overview', () => _xsite.overviewAttachment(orgUnitId));

  Future<SavedFile> _keep(String key, Future<XsiteFile> Function() download) async {
    final kept = _saved[key];
    if (kept != null && File(kept.path).existsSync()) return kept;
    final file = await download();
    final root = await (_dir ??= _makeDir().catchError((Object e) {
      _dir = null;
      throw e;
    }));
    final folder = Directory('${root.path}${Platform.pathSeparator}$key');
    await folder.create(recursive: true);
    final path = '${folder.path}${Platform.pathSeparator}${file.name}';
    await File(path).writeAsBytes(file.bytes, flush: true);
    return _saved[key] = (path: path, name: file.name, size: file.size);
  }

  Future<Directory> _makeDir() async {
    await _removeOld();
    // createTemp makes the folder for this user only (0700) on Linux and macOS.
    return _tempRoot().createTemp(_prefix);
  }

  /// Removes folders this app left in the temporary folder on earlier runs.
  Future<void> _removeOld() async {
    try {
      await for (final e in _tempRoot().list()) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (e is Directory && name.startsWith(_prefix)) {
          await e.delete(recursive: true).catchError((Object _) => e);
        }
      }
    } catch (_) {
      // The temporary folder can't be listed: nothing to tidy.
    }
  }

  /// Deletes every downloaded file.
  Future<void> clear() async {
    _saved.clear();
    final dir = _dir;
    _dir = null;
    try {
      final d = await dir;
      if (d != null && d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
    await _removeOld();
  }
}
