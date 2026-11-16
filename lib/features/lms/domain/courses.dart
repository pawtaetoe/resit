/// xSiTe's address, for links to a course's pages there.
const xsiteBase = 'https://xsite.singaporetech.edu.sg';

/// One course on xSiTe (SIT's Brightspace LMS).
class LmsCourse {
  final String orgUnitId;

  /// As xSiTe names it: "INF2004-Embedded Systems Programming [2026/27 T1]".
  final String name;

  /// e.g. "SIT-2610-INF2004".
  final String code;

  /// e.g. "2026/27 Trimester 1".
  final String semester;
  final DateTime? start;
  final DateTime? end;
  final bool isActive;
  final bool canAccess;
  final DateTime? lastAccessed;

  /// Relative path of the course image, if it has one.
  final String? imagePath;

  LmsCourse({
    required this.orgUnitId,
    required this.name,
    required this.code,
    required this.semester,
    this.start,
    this.end,
    this.isActive = true,
    this.canAccess = true,
    this.lastAccessed,
    this.imagePath,
  });

  static final _nameParts = RegExp(r'^([A-Z]{2,4}\d{3,4}[A-Z]?)\s*-\s*(.+?)(?:\s*\[([^\]]+)\])?$');

  /// "INF2004", or the last part of [code] if the name doesn't start with one.
  String get courseCode => _nameParts.firstMatch(name)?.group(1) ?? code.split('-').last;

  /// "Embedded Systems Programming", without the code and the term.
  String get title {
    final m = _nameParts.firstMatch(name);
    if (m == null) return name;
    return m.group(2)!.trim();
  }

  /// "2026/27 T1" from the name, or the semester as xSiTe gives it.
  String get termLabel => _nameParts.firstMatch(name)?.group(3) ?? semester;

  /// The course's home page on xSiTe.
  Uri get homeUrl => Uri.parse('$xsiteBase/d2l/home/$orgUnitId');
}

/// One item in a course's content (a file, link, video, ...) and whether the
/// user has completed it.
class ContentItem {
  final String orgUnitId;
  final int objectId;
  final String title;
  final int required;
  final int completed;

  ContentItem({
    required this.orgUnitId,
    required this.objectId,
    required this.title,
    required this.required,
    required this.completed,
  });

  bool get done => completed >= required;

  /// The item on xSiTe.
  Uri get url => Uri.parse('$xsiteBase/d2l/le/content/$orgUnitId/viewContent/$objectId/View');
}

/// How far through a course's content the user is.
class CourseProgress {
  final List<ContentItem> items;
  CourseProgress(this.items);

  int get required => items.fold(0, (a, i) => a + i.required);
  int get completed => items.fold(0, (a, i) => a + (i.completed > i.required ? i.required : i.completed));
  double get fraction => required == 0 ? 0 : completed / required;
  List<ContentItem> get todo => [for (final i in items) if (!i.done) i];
  List<ContentItem> get done => [for (final i in items) if (i.done) i];
}

/// One item in a course's content: a file, link, video, ...
class ContentTopic {
  final String orgUnitId;
  final int id;
  final String title;

  /// "File", "Link", "ContentService" (a video), ...
  final String type;

  /// Where it points: a web address for links, a path on xSiTe for files.
  final String url;
  final bool unread;
  final String description;

  ContentTopic({
    required this.orgUnitId,
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    this.unread = false,
    this.description = '',
  });

  /// A link to a web address the app may open directly: https only, so a
  /// plain-http, javascript:, intent: or malformed address isn't opened.
  bool get isLink => type == 'Link' && _linkUri != null;

  Uri? get _linkUri {
    final uri = Uri.tryParse(url.trim());
    return uri != null && uri.isScheme('https') && uri.host.isNotEmpty ? uri : null;
  }

  /// The file's extension in lower case ("pdf", "mp4", ...), if it's a file.
  String get extension {
    if (type != 'File') return '';
    final dot = url.lastIndexOf('.');
    return dot < 0 ? '' : url.substring(dot + 1).toLowerCase();
  }

  /// Where to open it: a link's own (https) address, otherwise its page on
  /// xSiTe.
  Uri get openUrl => (type == 'Link' ? _linkUri : null) ?? topicPage;

  /// The topic's page on xSiTe.
  Uri get topicPage => Uri.parse('$xsiteBase/d2l/le/content/$orgUnitId/viewContent/$id/View');
}

/// A folder in a course's content, holding topics and more folders.
class ContentModule {
  final int id;
  final String title;
  final List<ContentModule> modules;
  final List<ContentTopic> topics;

  ContentModule({required this.id, required this.title, this.modules = const [], this.topics = const []});

  /// Every topic in this folder and the folders inside it.
  Iterable<ContentTopic> get allTopics sync* {
    yield* topics;
    for (final m in modules) {
      yield* m.allTopics;
    }
  }
}

/// Orders courses by term (newest first), then by when they were last
/// opened (most recent first), then by code.
List<LmsCourse> sortCourses(Iterable<LmsCourse> courses) {
  final list = courses.toList();
  list.sort((a, b) {
    final byStart = (b.start ?? DateTime(0)).compareTo(a.start ?? DateTime(0));
    if (byStart != 0) return byStart;
    final bySeen = (b.lastAccessed ?? DateTime(0)).compareTo(a.lastAccessed ?? DateTime(0));
    if (bySeen != 0) return bySeen;
    return a.courseCode.compareTo(b.courseCode);
  });
  return list;
}
