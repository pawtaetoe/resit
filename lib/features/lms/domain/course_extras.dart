import 'package:resit/features/lms/domain/courses.dart';

/// A course's overview (its syllabus or introduction), as set in xSiTe's
/// content tool.
class CourseOverview {
  final String text;

  /// It has a file attached (a syllabus PDF, say).
  final bool hasAttachment;

  CourseOverview({required this.text, this.hasAttachment = false});

  bool get isEmpty => text.isEmpty && !hasAttachment;
}

/// A file read from xSiTe: its bytes and what xSiTe said about it.
class XsiteFile {
  /// A file name safe to save under (no folders, no odd characters).
  final String name;

  /// The MIME type xSiTe sent ("application/pdf"), or '' if none.
  final String type;
  final List<int> bytes;

  XsiteFile({required this.name, required this.type, required this.bytes});

  int get size => bytes.length;
}

/// What kind of file a topic is, for its list row: "PDF", "Word document",
/// ...; '' if it isn't a file or has no extension.
String fileTypeLabel(ContentTopic topic) => switch (topic.extension) {
      '' => '',
      'pdf' => 'PDF',
      'doc' || 'docx' || 'odt' || 'rtf' => 'Word document',
      'ppt' || 'pptx' || 'odp' => 'Slides',
      'xls' || 'xlsx' || 'ods' || 'csv' => 'Spreadsheet',
      'mp4' || 'mov' || 'webm' || 'm4v' => 'Video',
      'mp3' || 'm4a' || 'wav' => 'Audio',
      'html' || 'htm' => 'Web page',
      'txt' || 'md' || 'log' => 'Text',
      'zip' => 'ZIP archive',
      'png' || 'jpg' || 'jpeg' || 'gif' => 'Image',
      final ext => ext.length <= 5 ? '${ext.toUpperCase()} file' : 'File',
    };

/// Document types the app downloads and opens (in the app or another app
/// on the device); anything else (videos, web pages) opens on xSiTe.
const _documentTypes = {
  'pdf', 'doc', 'docx', 'odt', 'rtf', 'ppt', 'pptx', 'odp', 'xls', 'xlsx', 'ods', 'csv', 'zip', //
  'txt', 'md', 'log', //
  'png', 'jpg', 'jpeg', 'gif',
};

/// A file topic the app can download and open.
bool isDocument(ContentTopic topic) => topic.type == 'File' && _documentTypes.contains(topic.extension);

/// How a downloaded file is shown: PDFs, images and plain text in the app,
/// anything else handed to another app on the device.
enum FileView { pdf, image, text, otherApp }

/// The [FileView] for a file, from its name's extension.
FileView viewFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'pdf' => FileView.pdf,
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => FileView.image,
    'txt' || 'md' || 'log' => FileView.text,
    _ => FileView.otherApp,
  };
}

/// "2.3 MB", "640 KB", "12 bytes".
String fileSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes byte${bytes == 1 ? '' : 's'}';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// One thing to tick off in a checklist.
class ChecklistItem {
  final int id;
  final String name;
  final String description;
  final DateTime? dueDate;

  ChecklistItem({required this.id, required this.name, this.description = '', this.dueDate});
}

/// A group of items in a checklist. Items xSiTe didn't file under a
/// category are in one with an empty [name].
class ChecklistCategory {
  final int id;
  final String name;
  final String description;
  final List<ChecklistItem> items;

  ChecklistCategory({required this.id, required this.name, this.description = '', this.items = const []});
}

/// A course checklist: categories of items, in xSiTe's order. xSiTe doesn't
/// tell students' apps which items they've ticked, so this is the list only.
class Checklist {
  final String orgUnitId;
  final int id;
  final String name;
  final String description;
  final List<ChecklistCategory> categories;

  Checklist({
    required this.orgUnitId,
    required this.id,
    required this.name,
    this.description = '',
    this.categories = const [],
  });

  int get itemCount => categories.fold(0, (n, c) => n + c.items.length);

  /// The checklist on xSiTe.
  Uri get url => Uri.parse('$xsiteBase/d2l/lms/checklist/checklist.d2l?checklistId=$id&ou=$orgUnitId');
}

/// A survey you can see in a course.
class Survey {
  final String orgUnitId;
  final int id;
  final String name;
  final String description;
  final DateTime? start;
  final DateTime? end;
  final bool isAnonymous;

  Survey({
    required this.orgUnitId,
    required this.id,
    required this.name,
    this.description = '',
    this.start,
    this.end,
    this.isAnonymous = false,
  });

  bool isClosed(DateTime now) => end != null && end!.isBefore(now);
  bool opensLater(DateTime now) => start != null && start!.isAfter(now);
  bool isOpen(DateTime now) => !isClosed(now) && !opensLater(now);

  /// The survey's page on xSiTe.
  Uri get url => Uri.parse('$xsiteBase/d2l/lms/survey/user/survey_summary.d2l?si=$id&ou=$orgUnitId');
}

/// Open surveys first (closing soonest first), then ones that open later,
/// then closed ones; xSiTe's order otherwise.
List<Survey> sortSurveys(List<Survey> surveys, DateTime now) {
  int rank(Survey s) => s.isOpen(now) ? 0 : (s.opensLater(now) ? 1 : 2);
  final far = DateTime(9999);
  final indexed = [for (var i = 0; i < surveys.length; i++) (i, surveys[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    if (byRank != 0) return byRank;
    if (rank(a.$2) == 0) {
      final byEnd = (a.$2.end ?? far).compareTo(b.$2.end ?? far);
      if (byEnd != 0) return byEnd;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, s) in indexed) s];
}

/// A course's checklists and surveys. Either is null when the tool isn't
/// open to students in the course.
class ChecklistsAndSurveys {
  final List<Checklist>? checklists;
  final List<Survey>? surveys;

  ChecklistsAndSurveys({this.checklists, this.surveys});

  bool get isEmpty => (checklists?.isEmpty ?? true) && (surveys?.isEmpty ?? true);

  /// "2 checklists · 1 survey", or "None".
  String get summary {
    String count(int n, String what) => '$n $what${n == 1 ? '' : 's'}';
    final parts = [
      if (checklists case final c? when c.isNotEmpty) count(c.length, 'checklist'),
      if (surveys case final s? when s.isNotEmpty) count(s.length, 'survey'),
    ];
    return parts.isEmpty ? 'None' : parts.join(' · ');
  }
}
