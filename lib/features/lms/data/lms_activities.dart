import 'dart:convert';

import 'package:resit/features/lms/data/lms_service.dart';

// Course activities on xSiTe beyond content: announcements, assignments
// (dropbox), quizzes, grades and groups. Read from Brightspace's documented
// API (the "Valence" routes under /d2l/api/), the same family the content and
// progress calls use.

/// Plain text of a Brightspace rich-text block ({Text, Html}), or of a bare
/// string.
String richText(Object? v) {
  if (v is String) return v.trim();
  if (v is Map) {
    final text = v['Text'];
    if (text is String && text.trim().isNotEmpty) return text.trim();
    // Some blocks nest the text one level down: {Text: {Text, Html}}.
    if (text is Map) return richText(text);
    final html = v['Html'];
    if (html is String) return htmlToText(html);
  }
  return '';
}

/// Rough plain text from HTML: tags dropped, common entities decoded,
/// paragraphs kept apart.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(br|/p|/div|/li|/h\d)\b[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {'&nbsp;': ' ', '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'"};
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)));
  return s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n\s*(\n\s*)+'), '\n\n').trim();
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
double? _double(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

Object? _json(String body) {
  final t = body.trimLeft();
  return jsonDecode(t.startsWith('while(1);') ? t.substring(9) : t);
}

/// The list in a reply: a bare array, or an ObjectListPage's "Objects".
List<Map<String, Object?>> _list(Object? json) {
  final raw = json is List ? json : (json is Map ? (json['Objects'] ?? json['Items']) : null);
  return [
    for (final o in (raw as List?) ?? const [])
      if (o is Map) o.cast<String, Object?>(),
  ];
}

// ---------------------------------------------------------------------------
// Announcements
// ---------------------------------------------------------------------------

class Announcement {
  final String id;
  final String title;
  final String body;
  final DateTime? date;
  final int attachments;

  Announcement({required this.id, required this.title, required this.body, this.date, this.attachments = 0});
}

/// A course's announcements ("news"), newest first, without hidden or
/// unpublished ones.
List<Announcement> parseAnnouncements(String body) {
  final items = [
    for (final j in _list(_json(body)))
      if (j['IsHidden'] != true && j['IsPublished'] != false)
        Announcement(
          id: '${j['Id']}',
          title: (j['Title'] as String? ?? '').trim(),
          body: richText(j['Body']),
          date: _date(j['StartDate']) ?? _date(j['CreatedDate']),
          attachments: (j['Attachments'] as List?)?.length ?? 0,
        ),
  ];
  items.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
  return items;
}

// ---------------------------------------------------------------------------
// Assignments (dropbox folders)
// ---------------------------------------------------------------------------

class Assignment {
  final String orgUnitId;
  final int id;
  final String name;
  final String instructions;
  final DateTime? dueDate;

  /// Submissions close at this time (may be after the due date).
  final DateTime? endDate;
  final DateTime? startDate;
  final double? outOf;
  final int? gradeItemId;
  final bool isGroup;

  /// Your submissions, newest first. Null when xSiTe didn't say.
  final List<DateTime>? submissions;

  Assignment({
    required this.orgUnitId,
    required this.id,
    required this.name,
    this.instructions = '',
    this.dueDate,
    this.endDate,
    this.startDate,
    this.outOf,
    this.gradeItemId,
    this.isGroup = false,
    this.submissions,
  });

  bool get submitted => submissions?.isNotEmpty ?? false;
  DateTime? get lastSubmitted => submissions?.isNotEmpty == true ? submissions!.first : null;

  /// The deadline to show: the due date, else when submissions close.
  DateTime? get deadline => dueDate ?? endDate;

  Assignment withSubmissions(List<DateTime>? s) => Assignment(
        orgUnitId: orgUnitId,
        id: id,
        name: name,
        instructions: instructions,
        dueDate: dueDate,
        endDate: endDate,
        startDate: startDate,
        outOf: outOf,
        gradeItemId: gradeItemId,
        isGroup: isGroup,
        submissions: s,
      );

  /// The folder's submit page on xSiTe.
  Uri get url =>
      Uri.parse('${LmsService.base}/d2l/lms/dropbox/user/folder_submit_files.d2l?db=$id&grpid=0&isprv=0&bp=0&ou=$orgUnitId');
}

/// A course's dropbox folders, soonest deadline first (no deadline last),
/// without hidden ones.
List<Assignment> parseAssignments(String orgUnitId, String body) {
  final items = [
    for (final j in _list(_json(body)))
      if (j['IsHidden'] != true)
        Assignment(
          orgUnitId: orgUnitId,
          id: _int(j['Id']) ?? 0,
          name: (j['Name'] as String? ?? '').trim(),
          instructions: richText(j['CustomInstructions']),
          dueDate: _date(j['DueDate']),
          endDate: _date((j['Availability'] as Map?)?['EndDate']),
          startDate: _date((j['Availability'] as Map?)?['StartDate']),
          outOf: _double((j['Assessment'] as Map?)?['ScoreDenominator']),
          gradeItemId: _int(j['GradeItemId']),
          // DropboxType: 1 = group, 2 = individual.
          isGroup: _int(j['DropboxType']) == 1 || _int(j['GroupTypeId']) != null,
        ),
  ];
  items.sort(_byDeadline((a) => a.deadline));
  return items;
}

/// When each of your submissions to a folder was made, newest first.
List<DateTime> parseMySubmissions(String body) {
  final dates = <DateTime>[];
  void read(Map<String, Object?> s) {
    final d = _date(s['SubmissionDate']);
    if (d != null) dates.add(d);
  }

  for (final j in _list(_json(body))) {
    // Either Submission blocks, or EntityDropBox blocks holding them.
    if (j['Submissions'] is List) {
      for (final s in j['Submissions'] as List) {
        if (s is Map) read(s.cast<String, Object?>());
      }
    } else {
      read(j);
    }
  }
  dates.sort((a, b) => b.compareTo(a));
  return dates;
}

int Function(T, T) _byDeadline<T>(DateTime? Function(T) at) => (a, b) {
      final da = at(a), db = at(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    };

// ---------------------------------------------------------------------------
// Quizzes
// ---------------------------------------------------------------------------

class Quiz {
  final String orgUnitId;
  final int id;
  final String name;
  final String description;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? endDate;

  /// Null = unlimited.
  final int? attemptsAllowed;

  /// Minutes, when a time limit is enforced.
  final int? timeLimit;
  final int? gradeItemId;
  final bool isActive;

  Quiz({
    required this.orgUnitId,
    required this.id,
    required this.name,
    this.description = '',
    this.startDate,
    this.dueDate,
    this.endDate,
    this.attemptsAllowed,
    this.timeLimit,
    this.gradeItemId,
    this.isActive = true,
  });

  DateTime? get deadline => dueDate ?? endDate;

  /// The quiz's summary page on xSiTe (start or review attempts there).
  Uri get url => Uri.parse('${LmsService.base}/d2l/lms/quizzing/user/quiz_summary.d2l?qi=$id&ou=$orgUnitId');
}

/// A course's quizzes and the next page's address (null on the last page).
({List<Quiz> quizzes, String? next}) parseQuizzes(String orgUnitId, String body) {
  final json = _json(body);
  final quizzes = <Quiz>[];
  for (final j in _list(json)) {
    if (j['IsActive'] == false) continue;
    final attempts = j['AttemptsAllowed'] as Map?;
    final limit = j['SubmissionTimeLimit'] as Map?;
    quizzes.add(Quiz(
      orgUnitId: orgUnitId,
      id: _int(j['QuizId']) ?? 0,
      name: (j['Name'] as String? ?? '').trim(),
      description: richText((j['Description'] as Map?)?['Text'] ?? j['Description']),
      startDate: _date(j['StartDate']),
      dueDate: _date(j['DueDate']),
      endDate: _date(j['EndDate']),
      attemptsAllowed: attempts == null || attempts['IsUnlimited'] == true ? null : _int(attempts['NumberOfAttemptsAllowed']),
      timeLimit: limit != null && limit['IsEnforced'] == true ? _int(limit['TimeLimitValue']) : null,
      gradeItemId: _int(j['GradeItemId']),
    ));
  }
  final next = json is Map ? json['Next'] : null;
  return (quizzes: quizzes, next: next is String && next.isNotEmpty ? next : null);
}

List<Quiz> sortQuizzes(List<Quiz> quizzes) => quizzes..sort(_byDeadline((q) => q.deadline));

// ---------------------------------------------------------------------------
// Grades
// ---------------------------------------------------------------------------

class GradeEntry {
  final int? id;
  final String name;

  /// e.g. "Quiz", "Numeric", "Final Calculated".
  final String type;

  /// What xSiTe shows (e.g. "85 %", "A", "17 / 20").
  final String displayed;
  final double? points;
  final double? outOf;
  final double? weighted;
  final double? weightedOutOf;
  final String comment;

  GradeEntry({
    this.id,
    required this.name,
    this.type = '',
    this.displayed = '',
    this.points,
    this.outOf,
    this.weighted,
    this.weightedOutOf,
    this.comment = '',
  });

  /// The grade in one line: the displayed grade, else points.
  String get summary {
    if (displayed.trim().isNotEmpty) return displayed.trim();
    if (points != null && outOf != null) return '${_n(points!)} / ${_n(outOf!)}';
    if (points != null) return _n(points!);
    return '–';
  }

  static String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2);

  factory GradeEntry.fromJson(Map<String, Object?> j) => GradeEntry(
        id: _int(j['GradeObjectIdentifier']),
        name: (j['GradeObjectName'] as String? ?? '').trim(),
        type: (j['GradeObjectTypeName'] as String? ?? '').trim(),
        displayed: (j['DisplayedGrade'] as String? ?? '').trim(),
        points: _double(j['PointsNumerator']),
        outOf: _double(j['PointsDenominator']),
        weighted: _double(j['WeightedNumerator']),
        weightedOutOf: _double(j['WeightedDenominator']),
        comment: richText(j['Comments']),
      );
}

class CourseGrades {
  final List<GradeEntry> items;

  /// The released final grade, if any.
  final GradeEntry? finalGrade;

  CourseGrades(this.items, [this.finalGrade]);

  /// The grade for a grade item (e.g. a quiz's or an assignment's).
  GradeEntry? forItem(int? gradeItemId) {
    if (gradeItemId == null) return null;
    for (final g in items) {
      if (g.id == gradeItemId) return g;
    }
    return null;
  }
}

/// Your grade values in a course (only items with a grade released).
List<GradeEntry> parseGrades(String body) => [
      for (final j in _list(_json(body)))
        if (!(j['GradeObjectTypeName'] as String? ?? '').toLowerCase().contains('category')) GradeEntry.fromJson(j),
    ];

/// Your final grade value, or null.
GradeEntry? parseFinalGrade(String body) {
  final json = _json(body);
  return json is Map ? GradeEntry.fromJson(json.cast<String, Object?>()) : null;
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

class GroupMember {
  final String id;
  final String name;
  GroupMember(this.id, this.name);
}

class MyGroup {
  /// The group category, e.g. "Project Groups".
  final String category;
  final String name;
  final String description;
  /// Members whose names could be read (may be fewer than [memberCount]).
  final List<GroupMember> members;
  final int memberCount;

  MyGroup({
    required this.category,
    required this.name,
    this.description = '',
    this.members = const [],
    this.memberCount = 0,
  });
}

/// Your user id, from /users/whoami.
String parseWhoAmI(String body) {
  final json = _json(body);
  return json is Map ? '${json['Identifier'] ?? ''}' : '';
}

/// Group categories: (id, name).
List<({int id, String name})> parseGroupCategories(String body) => [
      for (final j in _list(_json(body)))
        if (_int(j['GroupCategoryId']) case final id?) (id: id, name: (j['Name'] as String? ?? '').trim()),
    ];

/// Groups in a category: name, description and member user ids.
List<({String name, String description, List<String> members})> parseGroups(String body) => [
      for (final j in _list(_json(body)))
        (
          name: (j['Name'] as String? ?? '').trim(),
          description: richText(j['Description']),
          members: [for (final e in (j['Enrollments'] as List?) ?? const []) '$e'],
        ),
    ];

/// Names by user id from the class list.
Map<String, String> parseClasslist(String body) => {
      for (final j in _list(_json(body)))
        '${j['Identifier']}': (j['DisplayName'] as String?)?.trim().isNotEmpty == true
            ? (j['DisplayName'] as String).trim()
            : '${j['FirstName'] ?? ''} ${j['LastName'] ?? ''}'.trim(),
    };

// ---------------------------------------------------------------------------
// Due soon
// ---------------------------------------------------------------------------

/// Something with a deadline: an assignment not yet submitted, or a quiz.
class DueItem {
  final String courseCode;
  final String title;
  final DateTime due;
  final bool isQuiz;
  final Uri url;

  DueItem({required this.courseCode, required this.title, required this.due, required this.isQuiz, required this.url});
}

/// Deadlines from [now] up to [within] ahead, plus anything due in the last
/// day that's still open, soonest first. Submitted assignments are left out.
List<DueItem> dueSoon(
  String courseCode,
  List<Assignment> assignments,
  List<Quiz> quizzes,
  DateTime now, {
  Duration within = const Duration(days: 14),
}) {
  bool soon(DateTime? d, DateTime? closes) {
    if (d == null) return false;
    if (d.isAfter(now.add(within))) return false;
    if (d.isAfter(now)) return true;
    // Past due but still open (late submissions) for a day: worth a nudge.
    return closes != null && closes.isAfter(now) && now.difference(d) < const Duration(days: 1);
  }

  final items = [
    for (final a in assignments)
      if (!a.submitted && soon(a.deadline, a.endDate))
        DueItem(courseCode: courseCode, title: a.name, due: a.deadline!, isQuiz: false, url: a.url),
    for (final q in quizzes)
      if (soon(q.deadline, q.endDate))
        DueItem(courseCode: courseCode, title: q.name, due: q.deadline!, isQuiz: true, url: q.url),
  ];
  items.sort((a, b) => a.due.compareTo(b.due));
  return items;
}
