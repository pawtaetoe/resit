import 'dart:convert';

import 'package:resit/features/lms/domain/courses.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';

// Reading xSiTe's course list and course content replies into the app's
// models. xSiTe is Brightspace; these are its documented "Valence" API routes
// under /d2l/api/ and the course widgets' JSON.

/// A course from an xSiTe course record.
LmsCourse lmsCourseFromJson(Map<String, Object?> j) {
  DateTime? date(String key) {
    final v = j[key];
    return v is String ? DateTime.tryParse(v)?.toLocal() : null;
  }

  final image = j['FormattedImageLink'];
  return LmsCourse(
    orgUnitId: '${j['OrgUnitId']}',
    name: (j['Name'] as String? ?? '').trim(),
    code: j['Code'] as String? ?? '',
    semester: j['SemesterName'] as String? ?? '',
    start: date('StartDate'),
    end: date('EndDate'),
    isActive: j['IsActive'] as bool? ?? true,
    canAccess: j['CanAccessCourse'] as bool? ?? true,
    lastAccessed: date('LastAccessed'),
    imagePath: image is String && image.isNotEmpty ? image : null,
  );
}

/// A content item's completion record.
ContentItem contentItemFromJson(Map<String, Object?> j) => ContentItem(
      orgUnitId: '${j['OrgUnitId']}',
      objectId: (j['ObjectId'] as num?)?.toInt() ?? 0,
      title: (j['Title'] as String? ?? '').trim(),
      required: (j['RequiredItems'] as num?)?.toInt() ?? 0,
      completed: (j['CompletedItems'] as num?)?.toInt() ?? 0,
    );

/// A content topic, or null if it's hidden.
ContentTopic? contentTopicFromJson(String orgUnitId, Map<String, Object?> j) {
  if (j['IsHidden'] == true) return null;
  final description = j['Description'];
  return ContentTopic(
    orgUnitId: orgUnitId,
    id: (j['TopicId'] as num?)?.toInt() ?? 0,
    title: (j['Title'] as String? ?? '').trim(),
    type: j['TypeIdentifier'] as String? ?? '',
    url: j['Url'] as String? ?? '',
    unread: j['Unread'] as bool? ?? false,
    description: description is Map ? (description['Text'] as String? ?? '').trim() : '',
  );
}

/// A content folder with its topics and sub-folders, or null if it's hidden.
ContentModule? contentModuleFromJson(String orgUnitId, Map<String, Object?> j) {
  if (j['IsHidden'] == true) return null;
  int order(Object? o) => o is Map ? (o['SortOrder'] as num?)?.toInt() ?? 0 : 0;
  List<Map<String, Object?>> sorted(Object? list) =>
      [for (final o in (list as List? ?? const [])) if (o is Map) o.cast<String, Object?>()]
        ..sort((a, b) => order(a).compareTo(order(b)));
  return ContentModule(
    id: (j['ModuleId'] as num?)?.toInt() ?? 0,
    title: (j['Title'] as String? ?? '').trim(),
    modules: [
      for (final m in sorted(j['Modules']))
        if (contentModuleFromJson(orgUnitId, m) case final module?) module,
    ],
    topics: [
      for (final t in sorted(j['Topics']))
        if (contentTopicFromJson(orgUnitId, t) case final topic?) topic,
    ],
  );
}

/// The items in one page of xSiTe's completion counts, and the next page's
/// address (null on the last page).
({List<ContentItem> items, String? next}) parseCompletions(String body) {
  final json = jsonDecode(stripGuard(body));
  final list = (json is Map ? json['Objects'] : null) as List? ?? const [];
  final next = json is Map ? json['Next'] : null;
  return (
    items: [
      for (final o in list)
        if (o is Map) contentItemFromJson(o.cast<String, Object?>()),
    ],
    next: next is String && next.isNotEmpty ? next : null,
  );
}

/// A course's table of contents: its top-level folders, in course order.
List<ContentModule> parseToc(String orgUnitId, String body) {
  final json = jsonDecode(stripGuard(body));
  final list = (json is Map ? json['Modules'] : null) as List? ?? const [];
  return contentModuleFromJson(orgUnitId, {'Modules': list})?.modules ?? const [];
}

/// Courses from xSiTe's "My Courses" list, newest term first and, within a
/// term, the most recently opened first.
List<LmsCourse> parseMyCourses(String body) {
  final json = jsonDecode(stripGuard(body));
  final list = (json is Map ? json['Courses'] : null) as List? ?? const [];
  return [
    for (final c in list)
      if (c is Map) lmsCourseFromJson(c.cast<String, Object?>()),
  ];
}
