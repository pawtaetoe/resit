import 'dart:convert';

import 'package:resit/features/lms/domain/course_extras.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';

// Reading xSiTe's course overview, checklist and survey replies into the
// app's models, from Brightspace's documented "Valence" API (LE 1.75).

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String _str(Object? v) => v is String ? v.trim() : '';

/// The rows of an ObjectListPage ({Next, Objects}) or a bare array, and the
/// next page's address (null on the last page).
({List<Map<String, Object?>> rows, String? next}) parsePage(String body) {
  final json = jsonDecode(stripGuard(body));
  final raw = json is List ? json : (json is Map ? json['Objects'] : null);
  final next = json is Map ? json['Next'] : null;
  return (
    rows: [
      for (final o in raw is List ? raw : const [])
        if (o is Map) o.cast<String, Object?>(),
    ],
    next: next is String && next.isNotEmpty ? next : null,
  );
}

/// A course's overview (Overview.Overview), or null if it says nothing.
CourseOverview? parseOverview(String body) {
  final json = jsonDecode(stripGuard(body));
  if (json is! Map) return null;
  final overview = CourseOverview(text: richText(json['Description']), hasAttachment: json['HasAttachment'] == true);
  return overview.isEmpty ? null : overview;
}

/// A checklist (ChecklistReadData) without its categories yet, or null if it
/// can't be read.
Checklist? checklistFromJson(String orgUnitId, Map<String, Object?> j) {
  final id = _int(j['Id']);
  if (id == null) return null;
  return Checklist(orgUnitId: orgUnitId, id: id, name: _str(j['Name']), description: richText(j['Description']));
}

/// A checklist with its categories and items (ChecklistCategoryReadData and
/// ChecklistItemReadData rows), each in xSiTe's sort order. Items in no
/// known category are listed last, under a category without a name.
Checklist withCategories(Checklist c, List<Map<String, Object?>> categories, List<Map<String, Object?>> items) {
  int order(Map<String, Object?> j) => _int(j['SortOrder']) ?? 0;
  final sortedItems = [...items]..sort((a, b) => order(a).compareTo(order(b)));
  final byCategory = <int, List<ChecklistItem>>{};
  for (final j in sortedItems) {
    final id = _int(j['ChecklistItemId']);
    if (id == null) continue;
    byCategory.putIfAbsent(_int(j['CategoryId']) ?? -1, () => []).add(ChecklistItem(
          id: id,
          name: _str(j['Name']),
          description: richText(j['Description']),
          dueDate: _date(j['DueDate']),
        ));
  }
  final sortedCategories = [...categories]..sort((a, b) => order(a).compareTo(order(b)));
  final known = <int>{};
  final result = <ChecklistCategory>[];
  for (final j in sortedCategories) {
    final id = _int(j['CategoryId']);
    if (id == null || !known.add(id)) continue;
    result.add(ChecklistCategory(
      id: id,
      name: _str(j['Name']),
      description: richText(j['Description']),
      items: byCategory[id] ?? const [],
    ));
  }
  final loose = [
    for (final e in byCategory.entries)
      if (!known.contains(e.key)) ...e.value,
  ];
  if (loose.isNotEmpty) result.add(ChecklistCategory(id: -1, name: '', items: loose));
  return Checklist(
    orgUnitId: c.orgUnitId,
    id: c.id,
    name: c.name,
    description: c.description,
    categories: result,
  );
}

/// A survey (SurveyReadData) a student can take, or null if it's inactive or
/// can't be read. The description is kept only where xSiTe shows it.
Survey? surveyFromJson(String orgUnitId, Map<String, Object?> j) {
  final id = _int(j['SurveyId']);
  if (id == null || j['IsActive'] == false) return null;
  final description = j['Description'];
  final shown = description is Map && description['IsDisplayed'] != false;
  return Survey(
    orgUnitId: orgUnitId,
    id: id,
    name: _str(j['Name']),
    description: shown ? richText(description['Text']) : '',
    start: _date(j['StartDate']),
    end: _date(j['EndDate']),
    isAnonymous: j['IsAnonymous'] == true,
  );
}

/// A name to save a downloaded file under: the Content-Disposition file
/// name if xSiTe sent one, else [fallback]; folders and odd characters
/// removed.
String downloadName(String? contentDisposition, String fallback) {
  String? name;
  final header = contentDisposition ?? '';
  final extended = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false).firstMatch(header);
  if (extended != null) {
    try {
      name = Uri.decodeComponent(extended[1]!.trim());
    } catch (_) {}
  }
  name ??= RegExp(r'filename\s*=\s*"([^"]*)"', caseSensitive: false).firstMatch(header)?[1] ??
      RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(header)?[1]?.trim();
  return safeFileName(name ?? '', fallback);
}

/// [name] without folders or characters a file system may refuse, at most
/// 120 characters (keeping the extension); [fallback] if nothing is left.
String safeFileName(String name, String fallback) {
  var s = name.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[^A-Za-z0-9 ._()\-]'), '_').trim();
  s = s.replaceAll(RegExp(r'^\.+'), '');
  if (s.isEmpty) s = fallback;
  if (s.length > 120) {
    final dot = s.lastIndexOf('.');
    final ext = dot > 0 && s.length - dot <= 10 ? s.substring(dot) : '';
    s = s.substring(0, 120 - ext.length) + ext;
  }
  return s;
}
