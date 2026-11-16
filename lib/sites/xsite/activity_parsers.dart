import 'dart:convert';

import 'package:resit/features/lms/domain/activities.dart';
import 'package:resit/sites/xsite/brightspace_json.dart';

// Reading xSiTe's course activity replies (announcements, assignments,
// quizzes, grades, groups) into the app's models, from Brightspace's
// documented "Valence" API routes under /d2l/api/.

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

/// A grade value record.
GradeEntry gradeEntryFromJson(Map<String, Object?> j) => GradeEntry(
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

/// Your grade values in a course (only items with a grade released).
List<GradeEntry> parseGrades(String body) => [
      for (final j in _list(_json(body)))
        if (!(j['GradeObjectTypeName'] as String? ?? '').toLowerCase().contains('category')) gradeEntryFromJson(j),
    ];

/// Your final grade value, or null.
GradeEntry? parseFinalGrade(String body) {
  final json = _json(body);
  return json is Map ? gradeEntryFromJson(json.cast<String, Object?>()) : null;
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
